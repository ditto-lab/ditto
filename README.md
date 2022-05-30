# ditto

Source repo: https://github.com/calvbore/dittoV0

This is the smart contract development and testing repo for Ditto Protocol.

## Set up foundry
https://github.com/gakonst/foundry/

```
curl -L https://foundry.paradigm.xyz | bash
```
Open a new terminal to load the latest `PATH`, and then run:
```
foundryup
```

Use the above command to update foundry as well.

## Set up this repo
After cloning, run the tests:
```
forge test
```

## Slither
`slither src/DittoMachine.sol`

## Echidna
`echidna-test --test-mode assertion --config src/test/echidna/echidna.config.yaml --contract DittoMachineTest src/test/echidna/DittoMachineTest.sol`

## Simplified Lifecycle of a Ditto


1. `Buyer1` makes an initial bid on thier desired NFT, `NFT1`.
  - Funds are transferred to the smart contract, a small fee taken and set asside to whomever will eventually sell `NFT1`.
  - A derivative of `NFT1`, `Ditto1`, is minted and transferred to `Buyer1`. `Ditto1` gives its owner the claim on `NFT1` if it's sold to the smart contract.
  - The minimum bid is set to some multiple of the price `Buyer1` paid for `Ditto1`. It will decrease over time until it reaches some value slightly above the `Buyer1`'s bid price.


2. `Buyer2` makes a second bid for `NFT1`
  - the bid satisfies the minimum bid defined in the smart contract. `Buyer1`'s bid is refunded to `Buyer1`, minus the fee paid.
  - A fee is taken from `Buyer2`'s bid. Half is sent to `Buyer1`, and half is set aside for the sale of `NFT1`.
  - `Ditto1` is transferred form `Buyer1` to `Buyer2`.
  - The minimum bid is set to some multiple of `Buyer2`'s bid price. It will decrease over time again.


3. `Seller1` sells `NFT1`
  - `Seller1` transfers `NFT1` to the smart contract.
  - `Ditto1` is burned.
  - `NFT1` is transferred to `Buyer2`.
  - `Buyer2`'s bid is transferred to `Seller1`, along with fees collected from previous bids.
