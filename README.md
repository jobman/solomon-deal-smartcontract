# Solomon Deal

Acton/Tolk implementation of the Solomon Deal escrow contract API described in
`../SMART_CONTRACT_API.md`.

The contract keeps compatibility with the existing message opcodes/body layout used by the Python
bot. Compared with the old `solomon_deal.tact` version, payouts are sent with `bounce: false`, so a
recipient wallet does not have to be initialized before it can receive TON.

## Build And Test

```bash
source $HOME/.acton/bin/env
acton build
acton test
```

Fish shell:

```fish
source $HOME/.acton/bin/env.fish
acton build
acton test
```

## Deploy

```bash
acton script --net testnet --explorer tonscan scripts/deploy.tolk 20260603
```

The optional numeric argument is stored in initial data and makes the deployed address unique. The
deployer wallet becomes `judgeSystem`.

Current testnet deployment addresses are recorded in
[`TESTNET_DEPLOYMENTS.md`](./TESTNET_DEPLOYMENTS.md).
