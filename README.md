<img src="data/nft-preview/quote-cover-active.svg" width="250" alt="Active OpenCover quote" />

<h1>OpenCover Contracts &nbsp;&nbsp;<img src="https://img.shields.io/badge/Version-v1-blue" alt="Version" /></h1>

OpenCover's smart contracts to make Nexus Mutual covers accessible on L2s.

## Overview

Users interact with OpenCover by submitting a quote on any supported L2 chain for a specific cover product.
This quote is represented by a dynamic NFT that changes depending on the quote's status (active, refunded, etc.) – [see previews](data/nft-preview/) of the NFT throughout the quote's lifecycle.

Once a quote is submitted a settlement period starts which allows OpenCover to purchase the corresponding cover on L1. In case the quote is not settled within this period users have the option to refund the quote.

When a quote is settled the transaction hash of the L1 cover purchase is attached to the quote along with the cover's expiry date.

## Repository Structure

| Folder          | Purpose                                             |
|-----------------|-----------------------------------------------------|
| `contracts/`    | Solidity contracts and interfaces for OpenCover.    |
|  `interface/`   | Interfaces for the OpenCover contracts.             |

### Deployment

The OpenCover contracts are deployed on _Optimism_, _Base_, _Arbitrum_ and _Polygon_ mainnets.

The `Quote` contract deployed to L2 chains uses an UUPS proxy to allow for upgradability.

#### Optimism

| Contract             | Address                                                                                                                    |
|----------------------|----------------------------------------------------------------------------------------------------------------------------|
| Quote                | [`0x0AC34fe133BdE3A2eF589a18A4E10b6a7d253829`](https://optimistic.etherscan.io/address/0x0AC34fe133BdE3A2eF589a18A4E10b6a7d253829) |
| Quote Implementation | [`0xA02ac8C77D4e2b52cA65C4f3C0534036269845b7`](https://optimistic.etherscan.io/address/0xA02ac8C77D4e2b52cA65C4f3C0534036269845b7) |

#### Base

| Contract             | Address                                                                                                                    |
|----------------------|----------------------------------------------------------------------------------------------------------------------------|
| Quote                | [`0xD68647555e5da198d50866334EEd647cbE3d1556`](https://basescan.org/address/0xD68647555e5da198d50866334EEd647cbE3d1556) |
| Quote Implementation | [`0x8101F97D399e110067Ff785b783d61545B5f18D2`](https://basescan.org/address/0x8101F97D399e110067Ff785b783d61545B5f18D2) |

#### Arbitrum

| Contract             | Address                                                                                                                    |
|----------------------|----------------------------------------------------------------------------------------------------------------------------|
| Quote                | [`0x0AC34fe133BdE3A2eF589a18A4E10b6a7d253829`](https://arbiscan.io/address/0x0AC34fe133BdE3A2eF589a18A4E10b6a7d253829) |
| Quote Implementation | [`0xA02ac8C77D4e2b52cA65C4f3C0534036269845b7`](https://arbiscan.io/address/0xA02ac8C77D4e2b52cA65C4f3C0534036269845b7) |

#### Polygon

| Contract             | Address                                                                                                                    |
|----------------------|----------------------------------------------------------------------------------------------------------------------------|
| Quote                | [`0x0AC34fe133BdE3A2eF589a18A4E10b6a7d253829`](https://polygonscan.com/address/0x0AC34fe133BdE3A2eF589a18A4E10b6a7d253829) |
| Quote Implementation | [`0xA02ac8C77D4e2b52cA65C4f3C0534036269845b7`](https://polygonscan.com/address/0xA02ac8C77D4e2b52cA65C4f3C0534036269845b7) |

