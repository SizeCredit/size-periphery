## size-periphery

### Coverage

```
forge coverage --report lcov && lcov --remove lcov.info -o lcov.info 'test/*' 'script/*' && genhtml lcov.info -o report --branch-coverage && open report/index.html
```