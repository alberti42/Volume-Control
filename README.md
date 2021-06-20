Volume Control (for Apple Music and Spotify)
=====================

Description
-----------

* This app allows you to directly control the volume of Apple Music and of Spotify using ``volume-up`` and ``volume-down`` keys from your keyboard.
* The app is especially useful when listening to music on AirPlay devices.
* You can adjust the finesse by which you step the volume.
* You can disable the heads-up display showing the volume status; this is useful when you are watching movies and you do not want to be distracted by the overlaid volume display.
* Using volume keys, the volume of the currently playing application (either Music or Spotify) is adjusted. If neither Music nor Spotify is playing, then the global volume will be adjusted.
* If you also press command key (⌘), you reverse the previous behavior. In this way you can still control the global volume even when Music or Spotify is plying.
* If the option ``Use ⌘ modifier`` is selected, then the app responds in the opposite manner, meaning that volume keys control the global volume, unless the command key is simultaneously pressed, in which case the volume of Music and Spotify is adjusted.

![Screenshot of the application](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/screenshot.png)

Why do you need this app?
-------------------------

* The volume of Apple Music (previously iTunes) cannot be directly controlled from the keyboard. Volume keys only affect the global system volume.
* You might desire to directly control Apple Music's volume from your keyboard, especially when listening to music on external speakers like AirPlay devices. The volume level of AirPlay devices depends on the volume controlled by Music, and not on the global volume. Unfortunately, Apple does not provide a way to adjust Music's volume from the keyboard. 
* You might desire to hide the volume heads-up overlay from your screen, especially when watching movies. This app can be configured to hide it.
* You might want to customize the step size when adjusting the volume.

How to get it installed?
------------------------

It is simple. There is no need of any installation.

* Just download either this [zip file](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Volume%20Control.zip).
* Decompress it.
* Drag the *Volume Control* app into your *Application* folder, or any other folder of your choice.
* Remove the extended attribute ``com.apple.quarantine`` from the downloaded application (see instructions below under *First download*; this is a necessary step since macOS Catalina).
* Run the *Volume Control* app. You should see the symbol of a "music note" appearing in your status bar, as shown in the screenshot above.
* The first time you launch the app, you should authorize it through the *General* panel of *Security & Privacy* of the *System Preferences*, as shown in the screenshot below. Follow instructions explained below under *Enabling control of Music and Spotify*.
* Enjoy listening to your favorite music with better volume control.

First download
--------------

* If you downloaded for the first time the app, you might encounter the error shown below.
	![Security and Privacy panel](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/firstDownload.png)
* The error occurs because of the extended attribute ``com.apple.quarantine``, which is automatically applied by Apple on all applications downloaded from the internet, unless officially authorized by Apple itself.
* To remove the quarantine extended attribute, type from terminal:

	``sudo xattr -d com.apple.quarantine "/Applications/Volume Control.app"``
	
	For more information, check [StackExchange](https://superuser.com/questions/526920/how-to-remove-quarantine-from-file-permissions-in-os-x).
* You might have to authorize from *Security & Privacy* of the *System Preferences* the first launch of the application

	![Security and Privacy panel](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/SecurityPrivacy.png)

* If you want to avoid these steps, you can download the source file and compile the application by yourself with Apple Xcode.

Permission to control Music's and Spotify's volume
--------------------------------------------------

The System Integrity Protection of macOS requires you to grant *Volume Control* access to Music and Spotify. The first time the application attempts to control their volume, you will be asked with a dialog window to grant access, as shown in the screenshot below.
![Security and Privacy Accessibility](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/SecurityPrivacyAccessibility.png)

Troubleshooting
---------------

* If you experience problems with permissions, especially if you upgrade from an old version, go to the *Accessibility* panel of *Security & Privacy* of the *System Preferences* (see screenshot below), and remove the entry "Volume Control". Make sure to close the app before you remove any permissions, or else you might end up being unable to use the keyboard until you reboot the machine. Once you open the app again, you will then be asked to authorize the application again.
* Verify that the app is authorized to control Music and Spotify, inspecting the panel *Automation* of *Security & Privacy* of the *System Preferences*. It could be helpful to disable and reenable the checkboxes for Music and Spotify shown in the screenshot below.
	![Security and Privacy Automation](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/SecurityPrivacyAutomation.png)

Requirements
------------

Mac OS X Mojave, Catalina, or Big Sur.

Credits
-------

This app has been inspired by *Volume for iTunes* by Yogi Patel. The icon has been designed by Alexandro Rei. The apple remote control has been adapted from iremotepipe by Steven Wittens. The utilization of MacOS native HUD is based on code written by Benno Krauss and on reverse engineering of */System/Library/CoreServices/OSDUIHelper.app/Contents/MacOS/OSDUIHelper*.

Contacts
--------

If you have any questions, you can contact me at a.alberti82@gmail.com. If you want to know what I do in the real life, visit [http://quantum-technologies.iap.uni-bonn.de/alberti/](http://quantum-technologies.iap.uni-bonn.de/alberti/).


Versions
--------

Note: you can download old versions by clicking on the links appearing down below.

* [1.7.0](http://quantum-technologies.iap.uni-bonn.de/alberti/iTunesVolumeControl/iTunesVolumeControl-v1.7.0.zip): Changed name to Volume Control; compatibility with Big Sur; compiled for universal bundle for Apple M1 and Intel.
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