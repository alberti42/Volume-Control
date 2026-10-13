#import "SpotifastApplication.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>
#import <errno.h>
#import <math.h>
#import <string.h>

static const NSTimeInterval kRequestTimeout = 0.1;
static const NSTimeInterval kVolumeSettleInterval = 0.5;
static const NSTimeInterval kHUDWriteInterval = 0.125;
static const NSUInteger kReplyLimit = 16 * 1024;

// Use one deadline for connect, write and read, including partial replies.
static BOOL WaitForSocket(int fd, short events, NSTimeInterval deadline)
{
    for (;;) {
        NSTimeInterval remaining = deadline - NSProcessInfo.processInfo.systemUptime;
        if (remaining <= 0) {
            errno = ETIMEDOUT;
            return NO;
        }
        struct pollfd descriptor = {fd, events, 0};
        int result = poll(&descriptor, 1, (int)ceil(remaining * 1000));
        if (result > 0)
            return YES; // send/recv/getsockopt report a closed or failed socket.
        if (result == 0) {
            errno = ETIMEDOUT;
            return NO;
        }
        if (errno != EINTR)
            return NO;
    }
}

@interface SpotifastApplication () {
    NSRunningApplication *_application;
    NSImage *_applicationIcon;
    NSString *_lastFailure;
    NSString *_lastWriteFailure;
    NSString *_playbackDeviceName;
    NSInteger _state;
    BOOL _hasVolume;
    NSTimeInterval _lastWriteTime;
    NSTimer *_hudWriteTimer;
    double _hudVolume;
    pid_t _hudProcessID;
    NSString *_hudDevice;
    void (^_hudCompletion)(BOOL);
}
- (NSString *)sendCommand:(NSString *)command;
- (BOOL)readPlayback;
- (void)resetPlayback;
@end

@implementation SpotifastApplication

- (instancetype)init
{
    // No SBApplication: Spotifast uses a local socket rather than Apple Events.
    if ((self = [super init])) {
        _bundleIdentifier = @"rocks.spotifast.Spotifast";
        [self resetPlayback];
        NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:_bundleIdentifier];
        if (appURL) {
            _applicationIcon = [[NSWorkspace sharedWorkspace] iconForFile:appURL.path];
            self.icon = _applicationIcon;
        }
    }
    return self;
}

- (void)resetPlayback
{
    [self cancelHUDVolume];
    _state = 0;
    _hasVolume = NO;
    _lastWriteTime = 0;
    _playbackDeviceName = nil;
    self.doubleVolume = -100;
    self.oldVolume = -1;
}

- (void)setEnabled:(BOOL)enabled
{
    if (_enabled == enabled)
        return;
    _enabled = enabled;
    [self resetPlayback];
    _lastFailure = nil;
    _lastWriteFailure = nil;
}

- (BOOL)isRunning
{
    NSRunningApplication *app = [NSRunningApplication runningApplicationsWithBundleIdentifier:self.bundleIdentifier].firstObject;
    if (app.processIdentifier != _application.processIdentifier) {
        [self resetPlayback];
        _lastFailure = nil;
        _lastWriteFailure = nil;
        if (app) {
            _applicationIcon = app.icon;
            self.icon = _applicationIcon;
        }
    }
    _application = app;
    return app != nil;
}

- (NSString *)socketFailure:(NSString *)reason
{
    [self resetPlayback];
    _lastFailure = reason;
    return nil;
}

- (NSString *)socketError
{
    int code = errno;
    NSString *reason = code == ETIMEDOUT ? @"socket did not answer within 100 ms" :
        [NSString stringWithFormat:@"socket: %@", [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil].localizedDescription];
    return [self socketFailure:reason];
}

// Spotifast 0.12 uses one prefixed line per connection. This is an internal
// protocol: reject unexpected replies and expose the failure in diagnostics.
- (NSString *)sendCommand:(NSString *)command
{
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"spotifast/instance.sock"];
    if (![path getFileSystemRepresentation:address.sun_path maxLength:sizeof(address.sun_path)])
        return [self socketFailure:@"socket path is too long"];
    address.sun_len = SUN_LEN(&address);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return [self socketError];
    @try {
        int noSignal = 1;
        if (fcntl(fd, F_SETFL, O_NONBLOCK) < 0 ||
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal)) < 0)
            return [self socketError];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + kRequestTimeout;
        if (connect(fd, (struct sockaddr *)&address, address.sun_len) < 0) {
            if (errno != EINPROGRESS && errno != EAGAIN && errno != EINTR)
                return [self socketError];
            if (!WaitForSocket(fd, POLLOUT, deadline))
                return [self socketError];
            int error = 0;
            socklen_t length = sizeof(error);
            if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) < 0)
                return [self socketError];
            if (error) {
                errno = error;
                return [self socketError];
            }
        }
        NSData *request = [[NSString stringWithFormat:@"spotifast:%@\n", command] dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger offset = 0;
        while (offset < request.length) {
            if (!WaitForSocket(fd, POLLOUT, deadline))
                return [self socketError];
            ssize_t count = send(fd, (const char *)request.bytes + offset, request.length - offset, 0);
            if (count < 0 && (errno == EAGAIN || errno == EINTR))
                continue;
            if (count <= 0)
                return [self socketError];
            offset += count;
        }
        NSMutableData *data = [NSMutableData data];
        while (data.length < kReplyLimit) {
            if (!WaitForSocket(fd, POLLIN, deadline))
                return [self socketError];
            char buffer[4096];
            ssize_t count = recv(fd, buffer, MIN(sizeof(buffer), kReplyLimit - data.length), 0);
            if (count < 0 && (errno == EAGAIN || errno == EINTR))
                continue;
            if (count < 0)
                return [self socketError];
            if (count == 0)
                return [self socketFailure:@"socket closed before a complete reply"];
            [data appendBytes:buffer length:count];
            if (memchr(buffer, '\n', count)) {
                NSString *reply = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (![reply hasPrefix:@"spotifast:"] || ![reply hasSuffix:@"\n"])
                    return [self socketFailure:@"unrecognised socket reply"];
                reply = [reply substringWithRange:NSMakeRange(10, reply.length - 11)];
                if ([reply containsString:@"\n"])
                    return [self socketFailure:@"unexpected extra socket reply"];
                return reply;
            }
        }
        return [self socketFailure:@"socket reply exceeds 16 KiB"];
    } @finally {
        close(fd);
    }
}

- (BOOL)readPlayback
{
    if (!self.enabled || ![self isRunning])
        return NO;
    NSString *reply = [self sendCommand:@"nowplaying"];
    if (!reply)
        return NO;
    if (![reply hasPrefix:@"now "]) {
        [self socketFailure:@"unrecognised nowplaying reply"];
        return NO;
    }
    NSString *output = [reply substringFromIndex:4];
    if ([output isEqualToString:@"stopped"]) {
        [self resetPlayback];
        _state = 'kPSS';
        _lastFailure = nil;
        return YES;
    }
    NSArray<NSString *> *fields = [output componentsSeparatedByString:@"\t"];
    NSInteger volume = 0;
    NSScanner *scanner = fields.count >= 7 ? [NSScanner scannerWithString:fields[6]] : nil;
    if (fields.count < 7 ||
        !([fields[0] isEqualToString:@"playing"] || [fields[0] isEqualToString:@"paused"]) ||
        ![scanner scanInteger:&volume] || !scanner.isAtEnd || volume < 0 || volume > 100) {
        [self socketFailure:@"unrecognised nowplaying fields"];
        return NO;
    }
    NSString *device = fields.count >= 12 && fields[11].length ? fields[11] : nil;
    BOOL deviceChanged = !((_playbackDeviceName == device) || [_playbackDeviceName isEqualToString:device]);
    if (deviceChanged) {
        [self cancelHUDVolume];
        self.oldVolume = -1;
        _lastWriteTime = 0;
    }
    // An accepted write is queued by Spotifast, not necessarily applied yet.
    // Preserve rapid key increments briefly, but always adopt a new device.
    BOOL settling = _lastWriteTime && NSProcessInfo.processInfo.systemUptime - _lastWriteTime < kVolumeSettleInterval;
    if (!_hasVolume || deviceChanged || (!settling && fabs(volume - self.doubleVolume) >= 1.0))
        self.doubleVolume = volume;
    _playbackDeviceName = [device copy];
    _state = [fields[0] isEqualToString:@"playing"] ? 'kPSP' : 'kPSp';
    _hasVolume = YES;
    _lastFailure = nil;
    return YES;
}

- (NSInteger)playerState
{
    return [self readPlayback] ? _state : 0;
}

- (BOOL)isUnresponsive
{
    return _lastFailure != nil;
}

- (BOOL)volumeReadTimedOut
{
    return !_hasVolume || _lastFailure != nil;
}

- (double)currentVolume
{
    return [self readPlayback] && _hasVolume ? self.doubleVolume : 0;
}

- (void)setCurrentVolume:(double)volume
{
    [self cancelHUDVolume];
    if (!isfinite(volume) || volume < 0 || !self.enabled || ![self isRunning] || !_hasVolume)
        return;
    NSString *device = _playbackDeviceName;
    if (![self readPlayback] || !_hasVolume)
        return;
    if (!(device == _playbackDeviceName || [device isEqualToString:_playbackDeviceName])) {
        [self socketFailure:@"playback device changed before the volume command"];
        return;
    }
    volume = fmin(volume, 100);
    // Keep fractional steps without repeatedly committing the same integer,
    // especially while a held key has already reached either volume limit.
    if (!_lastWriteFailure && lround(volume) == lround(self.doubleVolume)) {
        self.doubleVolume = volume;
        return;
    }
    NSString *reply = [self sendCommand:[NSString stringWithFormat:@"volume-set %ld", (long)lround(volume)]];
    if (![reply isEqualToString:@"ok"]) {
        if (reply)
            [self socketFailure:@"unrecognised volume-set reply"];
        _lastWriteFailure = _lastFailure;
        return;
    }
    _lastWriteFailure = nil;
    self.doubleVolume = volume;
    _lastWriteTime = NSProcessInfo.processInfo.systemUptime;
}

- (void)dealloc
{
    [_hudWriteTimer invalidate];
}

- (void)cancelHUDVolume
{
    [_hudWriteTimer invalidate];
    _hudWriteTimer = nil;
    _hudCompletion = nil;
    _hudDevice = nil;
}

- (void)setHUDVolume:(double)volume completion:(void (^)(BOOL))completion
{
    if (!isfinite(volume) || volume < 0 || !self.enabled || ![self isRunning] || !_hasVolume) {
        [self cancelHUDVolume];
        if (completion) completion(NO);
        return;
    }
    _hudVolume = fmin(volume, 100);
    _hudCompletion = [completion copy];
    if (_hudWriteTimer)
        return;
    _hudDevice = [_playbackDeviceName copy];
    _hudProcessID = _application.processIdentifier;
    NSTimeInterval delay = MAX(0, kHUDWriteInterval - (NSProcessInfo.processInfo.systemUptime - _lastWriteTime));
    // Only a drag schedules this one-shot timer. Keep its latest target,
    // and let a key press, restart or disable cancel the deferred write.
    __weak SpotifastApplication *weakSelf = self;
    _hudWriteTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        [weakSelf flushHUDVolume];
    }];
    [[NSRunLoop mainRunLoop] addTimer:_hudWriteTimer forMode:NSRunLoopCommonModes];
}

- (void)flushHUDVolume
{
    if (!_hudWriteTimer)
        return;
    double volume = _hudVolume;
    pid_t processID = _hudProcessID;
    NSString *device = _hudDevice;
    void (^completion)(BOOL) = _hudCompletion;
    [self cancelHUDVolume];
    if (!self.enabled || ![self isRunning] || processID != _application.processIdentifier)
        return;
    if (![self readPlayback] || !_hasVolume) {
        if (completion) completion(NO);
        return;
    }
    if (!(device == _playbackDeviceName || [device isEqualToString:_playbackDeviceName])) {
        [self socketFailure:@"playback device changed before the HUD volume command"];
        if (completion) completion(NO);
        return;
    }
    [self setCurrentVolume:volume];
    if (completion) completion(![self volumeReadTimedOut]);
}

- (void)scheduleVolumeVerification
{
    // No ScriptingBridge verification; the next interaction reads the socket.
}

- (NSString *)controlStatus
{
    if (!self.enabled)
        return @"local socket control disabled";
    if (_lastFailure)
        return _lastFailure;
    if (_lastWriteFailure)
        return [NSString stringWithFormat:@"last volume command failed: %@", _lastWriteFailure];
    return _state ? @"local socket responding" : @"local socket not queried yet";
}

- (NSString *)playbackDeviceName
{
    return _lastFailure ? nil : _playbackDeviceName;
}

@end
