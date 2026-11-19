# Local server-region provider bridge

RoValra Local does not call a third-party region API. It can optionally ask another installed extension to resolve a server region using Chromium's extension-to-extension messaging.

In the RoValra Local popup, enter the provider extension's 32-character ID. The provider must support this message:

```js
chrome.runtime.onMessageExternal.addListener((message, sender, sendResponse) => {
  if (message?.type !== 'ROVALRA_LOCAL_REGION_LOOKUP') return false;

  const { placeId, serverId } = message.payload || {};
  // Resolve the region using the provider's already-local/server-region data.
  // Do not return personal information.
  sendResponse({ region: 'Example region' });
  return false;
});
```

The provider's manifest may need to allow RoValra Local's extension ID in `externally_connectable` or otherwise support external extension messaging. The actual extension ID and message contract depend on the provider. No automatic probing or discovery of installed extensions is performed.
