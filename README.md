## size-periphery

Periphery contracts for the Size protocol.

This repository contains supporting contracts that interact with the [core Size protocol](https://github.com/SizeCredit/size-solidity). These contracts are designed to extend functionality, assist integrations, and provide additional utilities around the Size ecosystem.

### Overview

- Liquidator contracts
- Market Maker contracts
- Authorization contracts

### Coverage

```bash
forge coverage --no-match-coverage "(script|test)" --report lcov && genhtml lcov.info -o report --branch-coverage --ignore-errors inconsistent,corrupt && open report/index.html
```

### Disclaimer

This code is provided "as is" and has not undergone a formal security audit.

Use it at your own risk. The author(s) assume no liability for any damages or losses resulting from the use of this code. It is your responsibility to thoroughly review, test, and validate its security and functionality before deploying or relying on it in any environment.
