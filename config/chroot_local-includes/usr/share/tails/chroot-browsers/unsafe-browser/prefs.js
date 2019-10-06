user_pref("extensions.torbutton.inserted_button", true);
user_pref("extensions.torbutton.inserted_security_level", true);
// Disable proxying in the chroot
user_pref("extensions.torbutton.use_nontor_proxy", true);
user_pref("network.proxy.type", 0);
user_pref("network.proxy.socks_remote_dns", false);

// Without setting this, the Download Management page will not update
// the progress being made.
user_pref("browser.download.panel.shown", true);

// Disable searching from the URL bar. Mistyping e.g. the IP address
// to your router or some LAN resource could leak to the default
// search engine (this could include credentials, e.g. if something
// like the following is mistyped: ftp://user:password@host).
user_pref("keyword.enabled", false);

// Use the red theme
user_pref("extensions.activeThemeID", "{91a24c60-0f27-427c-b9a6-96b71f3984a9}");

// temporary fix
user_pref("extensions.webextensions.uuids", "{\"{91a24c60-0f27-427c-b9a6-96b71f3984a9}\":\"5df1b656-8c68-4696-aca5-682bd09bb455\"}");
