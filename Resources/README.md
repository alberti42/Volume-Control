iTunes-Volume-Control (compatible with Music app in Catalina)
=====================

Description
-----------

* This app allows you to directly control the volume of Apple Music as well as of Spotify using ``volume-up`` and ``volume-down`` hotkeys from your keyboard.
* <s>It also allows you to control the same iTunes volume by means of your Apple Remote control.</s>
* In general, the app is useful to control the volume of AirPlay devices.
* You can adjust the finesse by which you change the volume.
* You can disable the heads-up display showing the volume status; this is useful when you are watching movies and you do not want to be distracted by the overlay volume display.
* Using the volume keys, the volume of the currently playing application (either iTunes or Spotify) is controlled. If neither iTunes nor Spotify are playing music. Then the global volume will be affected by the volume keys.
* With command key (⌘), you can change the behavior whether you control the volume of the system or of the music player.

![alt tag](https://raw.github.com/alberti42/iTunes-Volume-Control/master/iTunes%20Volume%20Control/Images/screenshot.png)

Why do you need this app?
-------------------------

* The volume of Apple Music (previously iTunes) cannot be directly controlled from the keyboard. Volume keys only affect the global system volume.
* However, you might desire to directly control Apple Music's volume. This is especially relevant when listening to musing on external speakers like AirPlay devices. The volume level of AirPlay devices depends on iTunes's volume, and not on the global volume, which as a standard behavior, you can set using the volume keys.
* <s>iTunes does not respond to volume change from your Apple Remote. Again, Apple Remote would only change the system volume settings, leaving unaffected the volume of your AirPlay devices.</s>
* Sometimes you might desire to hide the volume heads-up overlay from your screen, especially when watching movies. This app can be configured to hide it.

How to get it installed?
------------------------

It is simple. There is no need of any installation.

* Just download either this [zip file](https://github.com/alberti42/iTunes-Volume-Control/raw/master/iTunes%20Volume%20Control.zip).
* Decompress it.
* Drag the *iTunes Volume Control* app into your *Application* folder, or any other folder of your choice.
* Run the *iTunes Volume Control* app and a "music note" symbol will appear in your status bar.
* The first time you launch the app, you should authorize it through the *General* panel of *Security & Privacy* of the *System Preferences*.
* If you experience problems with permissions, especially if you upgrade from an old version, go to *Accessibility* panel of *Privacy* of the *System Preferences* (see screenshot below), and try to remove the entry "iTunes Volume Control". Make sure to close the app before you remove any permissions, or else you might prevent controlling the keyboard until you reboot the machine. Once you open the app again, you will then be asked to authorize the application again.
* Enjoy listening to your favorite music with better volume control.

![alt tag](https://raw.github.com/alberti42/iTunes-Volume-Control/master/iTunes%20Volume%20Control/Images/SecurityPrivacyMojave.png)
	
Enabling control of iTunes and Spotify
--------------------------------------

The System Integrity Protection under Mojave requires you to grant *iTunes Volume Control* access to iTunes and Spotify. The first time the application attempts to control their volume, you will be asked with a dialog window to grant access.

If the application is running, but it is not able to read nor control the volume of the music player, you should then check that you have correctly granted access. You can change this in the *Automator* panel of *Security & Privacy* of the *System Preferences* (see screenshot below).

![alt tag](https://raw.github.com/alberti42/iTunes-Volume-Control/master/iTunes%20Volume%20Control/Images/AutomationScreenshotDark.png)

Requirements
------------

Mac OS X Mojave or Catalina.

Credits
-------

This app has been inspired by *Volume for iTunes* by Yogi Patel. The icon has been designed by Alexandro Rei. The apple remote control has been adapted from iremotepipe by Steven Wittens. The utilization of MacOS native HUD is based on code written by Benno Krauss and on reverse engineering of */System/Library/CoreServices/OSDUIHelper.app/Contents/MacOS/OSDUIHelper*.

Contacts
--------

If you have any questions, you can contact me at a.alberti82@gmail.com. If you want to know what I do in the real life, visit [http://quantum-technologies.iap.uni-bonn.de/alberti/](http://quantum-technologies.iap.uni-bonn.de/alberti/).


Versions
--------
* [1.6.8](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.8.zip): Fixed a bug when switching appearance to dark mode; improved volume control with apple key modifier.
* [1.6.7](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.7.zip): Improved compatibility with Catalina and new Music app.
* [1.6.6](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.6.zip): Restored compatibility with MacOS High Sierra and subsequent versions.
* [1.6.5](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.5.zip): Fixed a bug to avoid launching Spotify and iTunes at start of the app, if these program are not already running.
* [1.6.4](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.4.zip): Fixed crash on start due to failed permissions for AppleEvents.
* [1.6.3](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.3.zip): Removed codesigning that was causing the app to crash when starting.
* [1.6.2](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.2.zip): Fixed bug preventing Spotify's volume to be controlled.
* [1.6.1](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.1.zip): Improved visualization of volume status using even marks.
* [1.6.0](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.6.0.zip): Able to control Spotify, iTunes, and main volume.
* [1.5.3](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.5.3.zip): Made use of Mojave's native heads-up display to show the volume status.
* [1.5.2](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.5.2.zip): Fixed compatibility with Mojave. Prior versions are no longer supported. Fixed small bug on displaying the volume level when controlling it with the Apple Remote.
* [1.5.1](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.5.1.zip): Added the compatibility with Mac OS X versions greater than OS X 10.7 (Lion).
* [1.5](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.5.zip): Added the possibility to change the increment step on the volume. Backward compatible with Mavericks and Yosemite.
* [1.4.10](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.10.zip): Corrected bug on repositioning the volume indicator on right position.
* [1.4.9](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.9.zip): Started to prepare the transition to Yosemite look.
* [1.4.8](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.8.zip): Updates are now signed with DSA. This improves the security, e.g., preventing man-in-the-middle attacks.
* [1.4.7](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.7.zip): Changed icons and graphics to be compatible with retina display.
* [1.4.6](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.6.zip): Added the option to hide the icon from status bar. The icon reappears temporarily (for 10 seconds) by simply restarting the application. This gives the time to change the hide behavior as desired.
* [1.4.5](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.5.zip): Added the option to enable/disable automatic updates occurring once a week
* [1.4.4](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.4.zip): Corrected two bugs: the focus remains correctly on the selected application after changing the volume; cap lock does not prevent anymore the volume to be changed.
* [1.4.3](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.3.zip): Corrected bug: properly hide transparent panels when animations are completed (thanks to Justin Kerr Sheckler)
* [1.4.2](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.2.zip): Added iTunes icon to volume indicator. Corrected bug when iTunes is busy.
* [1.4.1](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.4.1.zip): Added automatic upgrade capability.
* 1.4: Added "mute" control.
* 1.3: Added graphic overlay panel indicating the volume level.
* 1.2: Added options, load at login, use CMD modifier.
* 1.1: Controlling iTunes volume using Apple Remote.
* 1.0: Controlling iTunes volume using keyboard "volume up"/"volume down".

Note: you can download old versions by clicking on the links which appear above here.

Requirements
------------

It is required Mac OS X 10.7 (Lion). The app has been tested with Mac OS X 10.7, 10.8.
