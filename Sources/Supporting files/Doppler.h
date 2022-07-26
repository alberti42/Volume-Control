/*
 * Doppler.h
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class DopplerTrack, DopplerApplication;

enum DopplerEPlS {
	DopplerEPlSStopped = 'kPSS',
	DopplerEPlSPlaying = 'kPSP',
	DopplerEPlSPaused = 'kPSp'
};
typedef enum DopplerEPlS DopplerEPlS;



/*
 * Doppler Playback Suite
 */

// playable track
@interface DopplerTrack : SBObject

- (NSString *) id;  // the id of the track
@property (copy, readonly) NSString *name;  // the title of the track
@property (copy, readonly) NSImage *artwork;  // a piece of art within a track
@property (copy, readonly) NSString *album;  // the album name of the track
@property (copy, readonly) NSString *albumArtist;  // the album artist of the track
@property (copy, readonly) NSString *artist;  // the artist of the track
@property BOOL loved;  // is this track loved?

- (void) reveal;  // reveal and select the specified track

@end

// The application program
@interface DopplerApplication : SBApplication

@property (copy, readonly) DopplerTrack *currentTrack;  // the currently playing track
@property (readonly) DopplerEPlS playerState;  // the current state of the audio player
@property BOOL shuffleEnabled;  // are songs played in random order?
@property NSInteger soundVolume;  // the sound output volume (0 = minimum, 100 = maximum)

- (void) play;  // play the current track in the playback queue
- (void) pause;  // pause the current track in the playback queue
- (void) nextTrack;  // advance to the next track in the playback queue
- (void) previousTrack;  // return to the previous track in the playback queue
- (void) toggleShuffleEnabled;  // toggle whether songs are played in a random order

@end

