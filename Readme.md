# Taming Hashicorp vault

Purpose of this repository is to show how to use Hashicorp Vault as personal easy to use password manager in bash shell.

The goal is to live the maxim "No clear text secrets in clear text files".

To achive the goal, handling secrets should be secure and easy. Ease of use is achieved by creating wrappers to vault binary and using them instead of vault binary directly. 

instead of 
```bash
curl –H 'token: YOURAPITOKEN' https://company.service.com
```
which leaves the token in your bash history + requires you to copy-paste the token, we do
```bash
curl –H 'token: $(get_secret companyapi)' https://company.service.com
```


## Installation

Installation guide can be found in [install.md](./docs/install.md)

## Usage

Usage guide can be found in [usage.md](./docs/usage.md)
