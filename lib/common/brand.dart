const brandName = 'ATCSkylink';

/// V2Board panel the login screen signs in to.
const panelApiBase = 'https://3d3f0f69.atcskylink.com';
const panelRegisterUrl = 'https://3d3f0f69.atcskylink.com/#/register';

/// Subscriptions are served from a host of their own, apart from the panel.
const panelSubscribeBase = 'https://api.bakaclient.org';

/// V2Board picks the subscription format from `flag`; `meta` asks for the
/// Clash Meta YAML, which carries VLESS and Hysteria2 nodes plain Clash drops.
const panelSubscribeFlag = 'meta';

/// Off until this build publishes its own releases.
const brandUpdatesEnabled = false;
