# action-generate-luacheckrc
GitHub action to generate up-to-date .luacheckrc for FantasyGrounds development.
It creates definitions by scanning FantasyGrounds rulesets and extensions to automatically whitelist variables.

## Usage

```yml
name: Update .luacheckrc

on:
  workflow_dispatch:
  schedule:
    - cron: 0 1 * * *
  push:
    paths:
      - '.luacheckrc_header'

jobs:
  generate:
    runs-on: ubuntu-latest
    name: generate new .luacheckrc
    steps:
    - uses: actions/checkout@v3
      with:
        fetch-depth: 0

    - name: Clone FG-Unofficial-Developers-Guild/CoreRPG
      uses: actions/checkout@v3
      with:
        repository: FG-Unofficial-Developers-Guild/CoreRPG
        # Getting FG code into your action working directory is up to you. This repo is not accessible.
        path: .fg/rulesets/CoreRPG
        fetch-depth: 0

    - name: Clone FG-Unofficial-Developers-Guild/5E
      uses: actions/checkout@v3
      with:
        repository: FG-Unofficial-Developers-Guild/5E
        # The ruleset folder in the file path cannot begin with a number or special character.
        path: .fg/rulesets/DND5E
        fetch-depth: 0

    - name: Clone bmos/FG-CoreRPG-Coins-Weight
      uses: actions/checkout@v3
      with:
        repository: bmos/FG-CoreRPG-Coins-Weight
        # The extension folder in the file path cannot begin with a number or special character.
        path: .fg/extensions/CoinsWeight
        fetch-depth: 0

    - name: Generate new .luacheckrc
      uses: FG-Unofficial-Developers-Guild/action-generate-luacheckrc@v1
      with:
        # Optional. This is the default value.
        target-path: '.luacheckrc'
        # Optional. This is the default value.
        header-path: '.luacheckrc_header'

    - name: Create pull request
      uses: peter-evans/create-pull-request@v4
      with:
        title: Update .luacheckrc
        commit-message: "test: update .luacheckrc"
        branch: update-luacheckrc
        delete-branch: true
```

## Arguments

* `target-path`: Path to generated `.luacheckrc`. Defaults to `.luacheckrc`.
* `header-path`: Path to `.luacheckrc` header, where you can put your own settings in. Defaults to `.luacheckrc_header`.

## License
The Unlicense
