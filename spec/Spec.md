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

## Design Overview

