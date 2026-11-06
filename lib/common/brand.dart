const brandName = 'ATCSkylink';

const _productionPanel = 'https://3d3f0f69.atcskylink.com';
const _productionSubscribe = 'https://api.bakaclient.org';

/// V2Board panel the login screen signs in to. A test build sets PANEL_URL;
/// every other build signs in to production.
const panelApiBase = String.fromEnvironment(
  'PANEL_URL',
  defaultValue: _productionPanel,
);

/// True for builds that point at a panel other than production.
const isTestPanel = panelApiBase != _productionPanel;

const panelRegisterUrl = '$panelApiBase/#/register';

/// Production serves subscriptions from a host of its own. A test panel
/// serves them itself unless PANEL_SUBSCRIBE_URL says otherwise.
const panelSubscribeBase = String.fromEnvironment(
  'PANEL_SUBSCRIBE_URL',
  defaultValue: isTestPanel ? panelApiBase : _productionSubscribe,
);

/// V2Board picks the subscription format from `flag`; `meta` asks for the
/// Clash Meta YAML, which carries VLESS and Hysteria2 nodes plain Clash drops.
const panelSubscribeFlag = 'meta';

/// Off until this build publishes its own releases.
const brandUpdatesEnabled = false;
