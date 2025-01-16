## size-periphery

### Coverage

```
forge coverage --report lcov && lcov --remove lcov.info -o lcov.info 'test/*' 'script/*' && genhtml lcov.info -o report --branch-coverage && open report/index.html
```

### Deploy

```
forge script script/Deploy.s.sol --rpc-url $RPC_URL --gas-limit 30000000 --sender $DEPLOYER_ADDRESS --account $DEPLOYER_ACCOUNT --ffi --verify -vvvvv
```