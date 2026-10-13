#import "SpotifastApplication.h"
#import <signal.h>
#import <math.h>

static const NSTimeInterval kSnapshotInterval = 0.3;
static const NSTimeInterval kSnapshotMaxAge = 3.0;
static const NSTimeInterval kVolumeSettleInterval = 0.5;
static const NSTimeInterval kVolumeWriteInterval = 0.05;

@interface SpotifastApplication () {
    NSRunningApplication *_application;
    NSImage *_applicationIcon;
    dispatch_queue_t _commandQueue;
    NSTimer *_snapshotTimer;
    NSDate *_snapshotDate;
    NSDate *_lastWriteDate;
    NSString *_lastFailure;
    NSString *_playbackDeviceName;
    NSInteger _state;
    NSUInteger _revision;
    NSUInteger _session; // Changes when the process or enabled preference changes.
    BOOL _hasVolume;
    BOOL _readInFlight;
    BOOL _writeInFlight;
    double _pendingVolume;
}
- (void)refreshSnapshot;
- (void)scheduleVolumeWrite:(double)volume;
- (void)writeVolume:(double)volume;
- (BOOL)canRunCommandForSession:(NSUInteger)session;
@end

@implementation SpotifastApplication

- (instancetype)init
{
    // Do not create an SBApplication: all communication is through Spotifast's
    // executable, discovered from the running app rather than the shell PATH.
    if ((self = [super init])) {
        _bundleIdentifier = @"rocks.spotifast.Spotifast";
        _commandQueue = dispatch_queue_create("io.alberti42.VolumeControl.spotifast", DISPATCH_QUEUE_SERIAL);
        _pendingVolume = -1;
        self.doubleVolume = -100;
        self.oldVolume = -1;
        NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:_bundleIdentifier];
        if (appURL) {
            _applicationIcon = [[NSWorkspace sharedWorkspace] iconForFile:appURL.path];
            self.icon = _applicationIcon;
        }
        __weak SpotifastApplication *weakSelf = self;
        _snapshotTimer = [NSTimer timerWithTimeInterval:kSnapshotInterval repeats:YES block:^(NSTimer *timer) {
            [weakSelf refreshSnapshot];
        }];
        [[NSRunLoop mainRunLoop] addTimer:_snapshotTimer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc
{
    [_snapshotTimer invalidate];
}

- (void)setEnabled:(BOOL)enabled
{
    if (_enabled == enabled)
        return;
    _enabled = enabled;
    _revision++;
    _session++;
    _pendingVolume = -1;
    _snapshotDate = nil;
    _lastWriteDate = nil;
    _lastFailure = nil;
    self.oldVolume = -1;
    if (enabled)
        [self refreshSnapshot];
}

- (BOOL)isRunning
{
    NSRunningApplication *app = [NSRunningApplication runningApplicationsWithBundleIdentifier:self.bundleIdentifier].firstObject;
    if (app.processIdentifier != _application.processIdentifier) {
        _revision++;
        _session++;
        _snapshotDate = nil;
        _lastWriteDate = nil;
        _lastFailure = nil;
        _playbackDeviceName = nil;
        _hasVolume = NO;
        _state = 0;
        _pendingVolume = -1;
        self.doubleVolume = -100;
        self.oldVolume = -1;
        if (app) {
            _applicationIcon = app.icon;
            self.icon = _applicationIcon;
        }
    }
    _application = app;
    return app != nil;
}

// The queue may still be finishing a read when the user disables or restarts
// the player. Check its session on the main thread before launching a command.
- (BOOL)canRunCommandForSession:(NSUInteger)session
{
    __block BOOL canRun = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        canRun = self.enabled && [self isRunning] && session == self->_session;
    });
    return canRun;
}

// Runs only on _commandQueue. A command addresses the already running player;
// it never launches the GUI. Bound the wait so a stuck CLI cannot fill the queue.
- (NSString *)runArguments:(NSArray<NSString *> *)arguments
             executableURL:(NSURL *)executableURL
                   failure:(NSString **)failure
{
    if (!executableURL) {
        *failure = @"executable not found";
        return nil;
    }
    NSTask *task = [[NSTask alloc] init];
    NSPipe *output = [NSPipe pipe];
    NSMutableData *data = [NSMutableData data];
    // Drain while the process runs: waiting for termination first can fill the
    // pipe with track metadata and block the child before it can exit.
    output.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
        @synchronized (data) {
            NSData *chunk = [handle availableData];
            if (chunk.length)
                [data appendData:chunk];
            else
                handle.readabilityHandler = nil;
        }
    };
    task.executableURL = executableURL;
    task.arguments = arguments;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    task.standardOutput = output;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_semaphore_signal(done);
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        output.fileHandleForReading.readabilityHandler = nil;
        *failure = [NSString stringWithFormat:@"command could not start: %@", error.localizedDescription];
        return nil;
    }
    [output.fileHandleForWriting closeFile];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) {
        if (task.running)
            kill(task.processIdentifier, SIGKILL);
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2));
        output.fileHandleForReading.readabilityHandler = nil;
        *failure = @"command did not answer within 2 s";
        return nil;
    }
    output.fileHandleForReading.readabilityHandler = nil;
    if (task.terminationStatus != 0) {
        *failure = [NSString stringWithFormat:@"command exited with status %d", task.terminationStatus];
        return nil;
    }
    NSString *result;
    @synchronized (data) {
        [data appendData:[output.fileHandleForReading readDataToEndOfFile]];
        result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    if (!result)
        *failure = @"invalid command output";
    return result;
}

- (void)refreshSnapshot
{
    if (!self.enabled || ![self isRunning] || _readInFlight || _writeInFlight)
        return;
    // The CLI acknowledges a queued action, not its completion. Let the app
    // apply the final write before reconciling the local cache with its snapshot.
    if (_lastWriteDate && -_lastWriteDate.timeIntervalSinceNow < kVolumeSettleInterval)
        return;
    _readInFlight = YES;
    NSUInteger revision = _revision;
    NSUInteger session = _session;
    NSURL *executableURL = _application.executableURL;
    dispatch_async(_commandQueue, ^{
        NSString *failure = nil;
        NSString *output = nil;
        if ([self canRunCommandForSession:session])
            output = [self runArguments:@[@"now-playing", @"--raw"] executableURL:executableURL failure:&failure];
        // Remove only the final newline: whitespace inside a track's fields
        // must not move the tab-separated volume field (index 6).
        if ([output hasSuffix:@"\n"])
            output = [output substringToIndex:output.length - 1];
        NSArray<NSString *> *fields = [output componentsSeparatedByString:@"\t"];
        NSInteger state = 0;
        NSInteger volume = 0;
        BOOL hasVolume = NO;
        NSString *deviceName = nil;
        if ([output isEqualToString:@"stopped"]) {
            state = 'kPSS';
        } else if (fields.count >= 7 && ([fields[0] isEqualToString:@"playing"] || [fields[0] isEqualToString:@"paused"])) {
            NSScanner *scanner = [NSScanner scannerWithString:fields[6]];
            hasVolume = [scanner scanInteger:&volume] && scanner.isAtEnd && volume >= 0 && volume <= 100;
            if (hasVolume)
                state = [fields[0] isEqualToString:@"playing"] ? 'kPSP' : 'kPSp';
            if (state && fields.count >= 12 && fields[11].length)
                deviceName = fields[11];
        }
        if (!state && !failure)
            failure = @"unrecognised now-playing output";
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_readInFlight = NO;
            [self isRunning];
            if (revision != self->_revision)
                return; // A newer write, restart or preference change won.
            BOOL deviceChanged = state && !((deviceName == self->_playbackDeviceName) ||
                [deviceName isEqualToString:self->_playbackDeviceName]);
            if (deviceChanged) {
                // A Connect transfer does not restart Spotifast. Adopt the new
                // target's volume even if it is close to the fractional cache,
                // and never restore the previous device's muted volume to it.
                self->_revision++;
                self.oldVolume = -1;
                self->_pendingVolume = -1;
                self->_lastWriteDate = nil;
            }
            if (state)
                self->_playbackDeviceName = [deviceName copy];
            self->_lastFailure = failure;
            self->_state = state;
            self->_hasVolume = hasVolume;
            self->_snapshotDate = state ? [NSDate date] : nil;
            if (hasVolume && (deviceChanged || fabs(volume - self.doubleVolume) >= 1.0))
                self.doubleVolume = volume;
        });
    });
}

- (BOOL)hasFreshSnapshot
{
    if (!_snapshotDate || _lastFailure)
        return NO;
    // During a key hold, the locally cached target is the current volume.
    if (_writeInFlight || (_lastWriteDate && -_lastWriteDate.timeIntervalSinceNow < kVolumeSettleInterval))
        return YES;
    return -_snapshotDate.timeIntervalSinceNow < kSnapshotMaxAge;
}

- (NSInteger)playerState
{
    return [self hasFreshSnapshot] ? _state : 0;
}

- (BOOL)isUnresponsive
{
    return ![self hasFreshSnapshot];
}

- (BOOL)volumeReadTimedOut
{
    return !_hasVolume || ![self hasFreshSnapshot];
}

- (double)currentVolume
{
    return [self volumeReadTimedOut] ? 0 : self.doubleVolume;
}

- (void)setCurrentVolume:(double)volume
{
    if (!isfinite(volume) || volume < 0 || !self.enabled || ![self isRunning] || [self volumeReadTimedOut])
        return;
    self.doubleVolume = fmin(volume, 100);
    _revision++;
    [self scheduleVolumeWrite:self.doubleVolume];
}

- (void)scheduleVolumeWrite:(double)volume
{
    _pendingVolume = volume;
    if (_writeInFlight)
        return;
    _writeInFlight = YES;
    // A key-hold ramp ticks every 10 ms. Keep its latest target, but do not
    // create a CLI process for each tick (at most 20 volume commands per s).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVolumeWriteInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.enabled || ![self isRunning] || self->_pendingVolume < 0) {
            self->_writeInFlight = NO;
            return;
        }
        double next = self->_pendingVolume;
        [self writeVolume:next];
    });
}

- (void)writeVolume:(double)volume
{
    _pendingVolume = -1;
    NSUInteger session = _session;
    NSURL *executableURL = _application.executableURL;
    NSString *percent = [NSString stringWithFormat:@"%ld", (long)lround(volume)];
    dispatch_async(_commandQueue, ^{
        NSString *failure = nil;
        if ([self canRunCommandForSession:session])
            [self runArguments:@[@"volume", percent] executableURL:executableURL failure:&failure];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_writeInFlight = NO;
            [self isRunning];
            if (session != self->_session)
                return;
            self->_lastFailure = failure;
            self->_lastWriteDate = [NSDate date];
            if (failure) {
                self->_pendingVolume = -1;
                self->_snapshotDate = nil;
                return;
            }
            if (self->_pendingVolume >= 0 && self.enabled) {
                double next = self->_pendingVolume;
                [self scheduleVolumeWrite:next];
            }
        });
    });
}

- (void)scheduleVolumeVerification
{
    // The base implementation verifies through ScriptingBridge in Debug.
    // This adapter reconciles through its regular CLI poll in every build.
    [self refreshSnapshot];
}

- (NSString *)controlStatus
{
    if (!self.enabled)
        return @"local command polling disabled";
    if (_lastFailure)
        return _lastFailure;
    return [self hasFreshSnapshot] ? @"local commands responding" : @"waiting for a current playback snapshot";
}

- (NSString *)playbackDeviceName
{
    return [self hasFreshSnapshot] ? _playbackDeviceName : nil;
}

@end
