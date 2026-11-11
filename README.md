# ExitIP

A macOS menu bar app that shows your public IPv4 address in green when it is a Mullvad exit and red when it is anything else.

It works whether the tunnel runs on the Mac or on the router, because the check looks at the address your traffic arrives from.

## Colours

| Colour | Meaning |
|---|---|
| Green | The address is a Mullvad exit |
| Red | The address belongs to someone else, usually your ISP |
| Grey | Checking, or the check failed |

The display goes grey as soon as the network changes, so it never shows an old green.

## Install

You need macOS 13 or later. There is no download: you build it from source, which takes a few seconds.

1. Install Apple's command line tools if you don't have them. Skip this if `git --version` already works.

   ```
   xcode-select --install
   ```

2. Clone the repo somewhere permanent.

   ```
   mkdir -p ~/Developer
   cd ~/Developer
   git clone https://github.com/nv0id/ExitIP.git
   cd ExitIP
   ```

3. Build and install.

   ```
   bash build.sh install
   ```

   This compiles the app, copies it to /Applications and launches it. The menu bar shows "checking" in grey, then your address in green or red.

4. Click the address in the menu bar and tick Launch at Login.

To build without installing, run `bash build.sh`. The app lands in the repo folder as `ExitIP.app`.

## Update

```
cd ~/Developer/ExitIP
git pull
bash build.sh install
```

Check that Launch at Login is still ticked afterwards. macOS can drop it when the app is rebuilt.

## Uninstall

Untick Launch at Login, choose Quit ExitIP from the menu, then delete `ExitIP.app` from /Applications.

## How it checks

Every 60 seconds, and on any network change or wake from sleep, it requests `https://ipv4.am.i.mullvad.net/json` and reads the `mullvad_exit_ip` field. That is the only network call it makes.

The menu shows the network owner, location and Mullvad server name, with Refresh and Copy IP.

## Troubleshooting

`_LSOpenURLsWithCompletionHandler() failed with error -10825` when launching means the binary was built for a newer macOS than the one you are running. `build.sh` pins the target to macOS 13 to prevent this, so check you are on 13 or later with `sw_vers -productVersion`.

## Limits

- IPv4 only. An IPv6 leak outside the tunnel would not show.
- Green says the exit is Mullvad. It says nothing about DNS leaks.
- Mullvad only. Other providers need a different check.
