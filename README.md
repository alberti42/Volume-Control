Volume Control (for Apple Music, Spotify, and Doppler music players)
=====================

:information_source: Compatible with macOS Sequoia.

:warning: If you upgraded the app and this does not start anymore, please read the instructions [below](#note_codesign) how to _codesign_ the app.

:warning: If you are running with Macos Ventura and later macOS versions, read the note [below](#ventura).

:warning: If you are running on an M1/M2 Apple computer, read the instructions [below](#note_codesign) how to launch the app.


Description
-----------

* This app allows you to directly control the volume of [Apple Music](https://apps.apple.com/app/apple-music/id1108187390), [Spotify](https://apps.apple.com/app/spotify-music-and-podcasts/id324684580), and [Doppler](https://brushedtype.co/doppler/) music players using ``volume-up`` and ``volume-down`` keys from your keyboard.
* The app is especially useful when listening to music on AirPlay devices.
* You can adjust the step size by which the volume is changed.
* You can disable the feedback bezel with the volume level. This is useful when you are watching movies and you do not want to be distracted by the overlaid bezel.
* Using volume keys, the volume of the currently playing application (either Music or Spotify) is adjusted. If neither Music nor Spotify is playing, then the system volume will be adjusted.
* When you press command key (``⌘``), you control the system volume regardless whether Music or Spotify is playing.
* The option ``Use ⌘ modifier`` toggles the app behavior, meaning that volume keys control the system volume, and when ``⌘`` is simultaneously pressed, the volume of Music and Spotify is then controlled.

![Screenshot of the application](Images/screenshot.png)

Why do you need this app?
-------------------------

* The volume of Apple Music (previously iTunes) cannot be directly controlled from the keyboard. Volume keys only affect the global system volume.
* You might desire to directly control Apple Music's volume from your keyboard, especially when listening to music on external speakers like AirPlay devices. The volume level of AirPlay devices depends on the volume controlled by Music, and not on the global volume. Unfortunately, Apple does not provide a way to adjust Music's volume from the keyboard. 
* You might desire to hide the volume heads-up overlay from your screen, especially when watching movies. This app can be configured to hide it.
* You might want to customize the step size when adjusting the volume.

How to get it installed?
------------------------

* Download the [zip file](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Volume%20Control.zip).
* Decompress it.
* Drag the *Volume Control* app into your *Application* folder, or any other folder of your choice.
* The first time you start the app, you will get an error message because the app is not signed.
![Unknown developer](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/Unknown_developer.png)
<br/>Sorry, I don't have the costly Apple Developer Subscription, which would allow me to sign the app as a certified developer.
* To circumvent the problem, from *Security & Privacy* of the *System Preferences*, click on the button *Open anyway*
![Open anyway panel](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/Open_anyway_panel.png)
* Run the *Volume Control* app. You should see the symbol of a "music note" appearing in your status bar, as shown in the screenshot above.
* The first time you launch the app, you should also authorize it through the *General* panel of *Security & Privacy* of the *System Preferences*, as shown in the screenshot below. For more information, see [below](#enabling_permissions).
* If you have an M1 Apple computer, you also need to sign the application with an ad-hoc signature. Follow the procedure explaiend [below](#M1_note).
* Enjoy listening to your favorite music with better volume control.

<a name="note_codesign"></a>
Running with newer Apple M1/M2 computers (Apple Silicon ARM64)
--------------------------------------------------------------------------

If you own an Apple Silicon computer (Apple M1 or M2), you cannot run the application without signinig it. This is a security change introduce first with Big Sur. For more details, check the [link](https://wiki.lazarus.freepascal.org/Code_Signing_for_macOS), where it is explained that all native ARM64 code must be signed or the operating system prevents its execution. In order to sign the application, follow these steps:

* Open the command line (i.e., launch the terminal app)
* Assuming that the application *Volume Control* is in the application folder, type the following command:
	``codesign --force --deep -s - /Applications/Volume\ Control.app``


<a name="ventura"></a>
Running with Macos Ventura
--------------------------------------------------
Many people reported problems in launching the application after a recent upgrade of Macos Ventura. This is a security feature of Macos Ventura. To overcome it, you need to compile the application by yourself using [Xcode](https://developer.apple.com/xcode/), which is provided by Apple on the App store for free. Aside from this security block, the application is fully compatible with Macos Ventrura.

The alternative option, which is for now excluded, is to have this app being certified by Apple. This is expensive and time consuming. Also, since the App 
is using undocumented functions of Macos, I suspect that Apple would not even grant an authorization to sell the app on the App store.

<a name="enabling_permissions"></a>
Permission to control Music's and Spotify's volume
--------------------------------------------------

The System Integrity Protection of macOS requires you to grant *Volume Control* access to Music and Spotify. The first time the application attempts to control their volume, you will be asked with a dialog window to grant access, as shown in the screenshot below. If you experience problems, remove the entry ``Volume Control`` from the Accessibility list and repeat the procedure.
![Security and Privacy Accessibility](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/SecurityPrivacyAccessibility.png)

Troubleshooting
---------------

* If you experience problems with permissions, especially if you upgrade from an old version, go to the *Accessibility* panel of *Security & Privacy* of the *System Preferences* (see screenshot below), and remove the entry "Volume Control". Make sure to close the app before you remove any permissions, or else you might end up being unable to use the keyboard until you reboot the machine. Once you open the app again, you will then be asked to authorize the application again.
* Verify that the app is authorized to control Music and Spotify, inspecting the panel *Automation* of *Security & Privacy* of the *System Preferences*. It could be helpful to disable and reenable the checkboxes for Music and Spotify shown in the screenshot below.
	![Security and Privacy Automation](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Images/SecurityPrivacyAutomation.png)

Requirements
------------

Compatible with macOS Big Sur and subsequent versions.


Credits
-------

This app has been inspired by *Volume for iTunes* by Yogi Patel. The icon has been designed by Alexandro Rei. The apple remote control has been adapted from `iremotepipe` by Steven Wittens. The utilization of MacOS native HUD is based on code written by Benno Krauss and on reverse engineering of */System/Library/CoreServices/OSDUIHelper.app/Contents/MacOS/OSDUIHelper*. Support for 
Doppler Music Player has been provided by Ed Wellbrook.


Donations
---------

I would be grateful for any donation to support the development of this plugin.

[<img src="Images/buy_me_coffee.png" width=300 alt="Buy Me a Coffee QR Code"/>](https://buymeacoffee.com/alberti)

Author
------

- **Author:** Andrea Alberti
- **GitHub Profile:** [alberti42](https://github.com/alberti42)
- **Donations:** [![Buy Me a Coffee](https://img.shields.io/badge/Donate-Buy%20Me%20a%20Coffee-orange)](https://buymeacoffee.com/alberti)

Feel free to contribute to the development of this plugin or report any issues in the [GitHub repository](https://github.com/alberti42/Volume-Control/issues).

Versions
--------

Note: you can download old versions by clicking on the links appearing down below.

* [1.7.6](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/VolumeControl-v1.7.6.zip): Fixes some bugs with the volume not reaching zero.
* [1.7.5](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/VolumeControl-v1.7.5.zip): Universal application compiled to run natively on both Apple Silicon and Apple Intel.
* [1.7.4](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/VolumeControl-v1.7.4.zip): Added support for Doppler Music Player thanks to Ed Wellbrook.
* [1.7.3](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/VolumeControl-v1.7.3.zip): Made acoustic feedback when changing volume more responsive. Fixed minor bugs. Switch to updates through GitHub repository.
* [1.7.2](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/VolumeControl-v1.7.2.zip): Fixed appearance of icon according to Monterey MacOS style.
* [1.7.0](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/VolumeControl-v1.7.0.zip): Changed name to Volume Control; compatibility with Big Sur; compiled for universal bundle for Apple M1 and Intel.
* [1.6.8](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.8.zip): Fixed a bug when switching appearance to dark mode; improved volume control with apple key modifier.
* [1.6.7](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.7.zip): Improved compatibility with Catalina and new Music app.
* [1.6.6](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.6.zip): Restored compatibility with MacOS High Sierra and subsequent versions.
* [1.6.5](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.5.zip): Fixed a bug to avoid launching Spotify and iTunes at start of the app, if these program are not already running.
* [1.6.4](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.4.zip): Fixed crash on start due to failed permissions for AppleEvents.
* [1.6.3](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.3.zip): Removed codesigning that was causing the app to crash when starting.
* [1.6.2](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.2.zip): Fixed bug preventing Spotify's volume to be controlled.
* [1.6.1](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.1.zip): Improved visualization of volume status using even marks.
* [1.6.0](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.6.0.zip): Able to control Spotify, iTunes, and main volume.
* [1.5.3](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.5.3.zip): Made use of Mojave's native heads-up display to show the volume status.
* [1.5.2](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.5.2.zip): Fixed compatibility with Mojave. Prior versions are no longer supported. Fixed small bug on displaying the volume level when controlling it with the Apple Remote.
* [1.5.1](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.5.1.zip): Added the compatibility with Mac OS X versions greater than OS X 10.7 (Lion).
* [1.5](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.5.zip): Added the possibility to change the increment step on the volume. Backward compatible with Mavericks and Yosemite.
* [1.4.10](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.10.zip): Corrected bug on repositioning the volume indicator on right position.
* [1.4.9](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.9.zip): Started to prepare the transition to Yosemite look.
* [1.4.8](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.8.zip): Updates are now signed with DSA. This improves the security, e.g., preventing man-in-the-middle attacks.
* [1.4.7](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.7.zip): Changed icons and graphics to be compatible with retina display.
* [1.4.6](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.6.zip): Added the option to hide the icon from status bar. The icon reappears temporarily (for 10 seconds) by simply restarting the application. This gives the time to change the hide behavior as desired.
* [1.4.5](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.5.zip): Added the option to enable/disable automatic updates occurring once a week
* [1.4.4](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.4.zip): Corrected two bugs: the focus remains correctly on the selected application after changing the volume; cap lock does not prevent anymore the volume to be changed.
* [1.4.3](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.3.zip): Corrected bug: properly hide transparent panels when animations are completed (thanks to Justin Kerr Sheckler)
* [1.4.2](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.2.zip): Added iTunes icon to volume indicator. Corrected bug when iTunes is busy.
* [1.4.1](https://raw.githubusercontent.com/alberti42/Volume-Control/main/Releases/iTunesVolumeControl-v1.4.1.zip): Added automatic upgrade capability.
* 1.4: Added "mute" control.
* 1.3: Added graphic overlay panel indicating the volume level.
* 1.2: Added options, load at login, use CMD modifier.
* 1.1: Controlling iTunes volume using Apple Remote.
* 1.0: Controlling iTunes volume using keyboard "volume up"/"volume down".
