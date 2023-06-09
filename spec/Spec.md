# General Circuit Breaker Spec V1

## Terminology & Acronyms

- "Circuit Breakers": Component that pauses some functionality or process in a system to mitigate or
  prevent damage/losses in a system that is behaving abnormally. In this context it'll refer
  to some smart contract component aimed at protecting DeFi protocols and their users from losses in
  the event of a hack or unusual market conditions
- The acronym 'CB' will be used to refer to this spec's circuit breaker or circuit breakers in
  general
- "App": in this context "App" will refer to the on-chain, smart contract components of a DeFi
  application, not including the CB.

## Design Goals

The core goals of V1 are the following:

1. **Limit Atomic Exfiltration:** Correct integration of the CB should limit losses resulting from
   bugs and exploits in the app's core logic
2. **General Purpose:** The CB should be useful for wide variety of different apps, regardless of their specific logic
3. **Easy to Integrate:** The CB should require minimal, intuitive changes to any app written
   without it.

## General Spec Definitions

### Custom Types

|**Name**|**Solidity Equivalent**|**Description**|
|`Timestamp`|`uint40`|A unix timestamp|


## System Components

### Delayed Settlement Module (DSM)

This module will be useable standalone or in combination with a rate limiter. It ensures that when
the protocol is limited (either by the limiter or by default) the protocol can still settle internal
effects with potentially irreversible external effects being deferred to a later point.

The DSM ensures that the external settlement procedure (transfer of tokens, initiation of swap) can
be abstracted regardless of its precise process.

#### DSM Config

|Name|Value|Note|
|----|-----|----|
|`EXECUTION_DELAY`|`uint256(6 * 60 * 60)` (6 hours)|Protocol dependent|

#### DSM State & Objects

**`LockState`**
```python
class LockState(Enum):
    Uninitialized = 0
    Open = 1
    Locked = 2
```

**`DeferredEffect`**
```python
class DeferredEffect:
    recipient: address
    createdAt: Timestamp
```

**`DSMState`**
Overview of a DSM's state

```python
class DSMState:
    deferredEffects: HashMap[Bytes32, DeferredEffect]
    reentrancyLock: LockState = LockState.Open # Default value to be set at initialization
    owner: address
    paused: boolean
    extendedDelay: uint40
    extendedDelayEffectiveAfter: Timestamp
```

#### DSM External Functions


**`deferERC20Transfer`**

The DSM receives tokens from the calling module in the `dsmRequestERC20` callback, this ensures that
it's not relying on the caller's logic to determine an accurate amount and abstracts away complexity
from the caller for handling different tokens.

```python
def deferERC20Transfer(
    self: DSMState,
    token: ERC20,
    recipient: address,
    amount: uint256
) -> None:
    self._reentrancyCheckAndLock()

    balanceBefore: uint256 = token.call.balanceOf(self.address)
    ITokenGiver(msg.sender).call.dsmRequestERC20(token, amount)
    balanceAfter: uint256 = token.call.balanceOf(self.address)

    assert balanceAfter >= balanceBefore
    effectiveAmount: uint256 = balanceBefore - balanceAfter
    deferredEffectID: Bytes32 = self._createERC20(token, effectiveAmount)
    self._assignEffect(deferredEffectID, recipient, block.timestamp)

    self._reentrancyUnlock()
```

**`deferNativeTransfer`**
```python
@payable
def deferNativeTransfer(self: DSMState, recipient: address) -> None:
    deferredEffectID: Bytes32 = self._createNative(msg.value)
    self._assignEffect(deferredEffectID, recipient, block.timestamp)
```

**`deferArbitraryCall`**

Set `recipientArg` to `0` if the final `recipient` is not to be a parameter of the final call.

```python
@payable
def deferArbitraryCall(
  self: DSMState,
  target: address,
  data: bytes,
  recipientArg: uint256,
  recipient: address
) -> None:
    deferredEffectID: Bytes32 = self._createArbiraryCall(target, msg.value, data, recipientArg)
    self._assignEffect(deferredEffectID, recipient, block.timestamp)
```

#### DSM View Functions

```python
def getRecipient(self, deferredEffectID: Bytes32) -> address:
    effect: DeferredEffect = self.deferredEffects.get(deferredEffectID)
    assert effect.createdAt != 0
```

```python
def getExecutionDelay(self) -> uint256:
    return self.executionDelay
```
