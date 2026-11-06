# WiVoice

WiVoice streams Mac system audio and, optionally, microphone audio to a browser on another device on the same local network. It is intended for Macs whose built-in audio does not work, including Hackintosh systems.

## Download

Open the **Releases** page and download the latest `WiVoice-macOS-Ventura-x86_64.zip`. Expand it and move `WiVoice.app` to Applications. This build targets Intel Macs running macOS Ventura 13 or later.

This is an unsigned development build. macOS may ask you to confirm the first launch. A Developer ID signature and Apple notarization are needed for a seamless public install.

## Audio setup

macOS needs an audio output device before it can capture system audio. If the Mac has no working audio device, install a virtual device such as [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole#installation-instructions), then choose **BlackHole 2ch** in System Settings → Sound → Output. This routes Mac audio into WiVoice; the Mac itself will not play that audio through speakers.

On first use, allow WiVoice in System Settings → Privacy & Security → Screen Recording. Click **Start streaming** in WiVoice, then open the displayed `http://…:8765` address on the receiving device and tap **Listen**. Both devices must be on the same Wi-Fi network.

To also send the Mac microphone, enable **Include microphone** before starting. Allow microphone access when macOS asks. The receiving device plays microphone and system audio together; the mic toggle is off by default.

The receiver page displays incoming packet counts and a signal meter so you can tell whether audio is reaching the device or the Mac is sending silence.

The stream is unencrypted and intended for a trusted local network.

## Build from source

Requires Xcode 14.3.1 or newer and macOS 13 or newer. Run:

```sh
./build-app.sh
```

The app bundle is written to `dist/WiVoice.app`.
