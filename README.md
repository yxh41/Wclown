# WCRClownStandalone

Independent clean-room reimplementation scaffold based on observed runtime behavior. It does not embed or load WCRefine.dylib.

## Safety state
- All behavior is local display/runtime override only.
- No payment requests or server messages are modified.
- Unverified WeChat hooks are disabled by default.
- The development package must not be installed as a production release.

## Planned features
1. Master switch
2. Chat text
3. Chat image
4. Message time
5. Message sorting
6. Chat time
7. Yin/Yang side swap
8. Transfer display amount
9. Transfer override persistence until WeChat exits
