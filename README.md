# privy-cardano-poc

Experimental integration of [privy.io](https://www.privy.io/) with Cardano

## Control Flow

### Initialisation

We authenticate with privy and ask for the user's public key.
Then we use this public key to determine the user's Cardano address.

```mermaid
sequenceDiagram
  browser->>privy: authenticate
  privy->>browser: public key
  browser->>backend: ask for wallet address and balance
  backend->> browser:
```

### Building a transaction

```mermaid
sequenceDiagram
  browser->>backend: Build transaction
  backend->>browser: Tx
  browser->>privy: Sign (Ed25519)
  privy->>browser: Signature
  browser->>backend: Submit tx
```