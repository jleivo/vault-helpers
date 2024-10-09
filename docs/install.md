# Installation

During the installation we will modify the default configuration and enable the KV2 secrets engine. We reduce the security to allow for easier usage of this tool.

## Install binaries

Do the basic installation as per the following link: https://developer.hashicorp.com/vault/docs/install

## Configure TLS certificates

In order to access the vault we need to create and trust our self-signed certificate. If you have the possibility of using a trusted CA, this step can be skipped.

The self-signed certificate created here has multiple SAN's to allow for multiple ways to connect to the vault. By default it has

- localhost
- 127.0.0.1

should you need to add other SAN'S you can do so by modifying the last line of this command. Use the DNS and IP examples as a reference.

Certificate validity is set to 365 days, but you might want to have a longer validity period for your own use case. Adjust the validity period by changing the -days parameter.

```bash
openssl req -x509 -nodes -newkey rsa:2048 -keyout tls.key -out vault.crt -days 365 -subj "/CN=localhost" -reqexts SAN -extensions SAN -config <(echo -e "[ req ]\ndistinguished_name=req_distinguished_name\n[ req_distinguished_name ]\n[ SAN ]\nsubjectAltName=DNS:localhost,IP:127.0.0.1")
```

After this step you should have a `vault.crt` and `tls.key` file in the current directory. These should be moved to the vault tls directory, which is `/opt/vault/tls/` by default.

```bash
sudo mv tls.key /opt/vault/tls/ 
sudo cp vault.crt /opt/vault/tls/tls.crt
```

After this step you need to, in the case of self-signed certificate, make the certificate trusted by your system. This can be done by copying the `vault.crt` file to `/usr/local/share/ca-certificates/` and running `sudo update-ca-certificates`.

Finally, restart vault to load the new certificates.

```bash
sudo systemctl restart vault
```
## Modify bash to our own liking

I found these to be needed in my .bashrc to allow for easier usage and remove warning message related to DBUS.

```bash	
export DBUS_SESSION_BUS_ADDRESS=/dev/null
export VAULT_ADDR=https://127.0.0.1:8200
```

In addition, the vault helper library needs to be added to your .bashrc file. This is done by copying the vault_lib.sh to your ~/.local/lib/ folder and sourcing it from your .bashrc file.

```bash
mkdir -p ~/.local/lib
wget https://raw.githubusercontent.com/jleivo/vault-helpers/refs/heads/master/vault_lib.sh -O ~/.local/lib/vault_lib.sh
echo "source ~/.local/lib/vault_lib.sh" >> ~/.bashrc
```

load your updated .bashrc file.

```bash
source ~/.bashrc
```

## Initialize Vault

Here we do our first deviation from the standard installation guide. We will initialize the vault with a single key share and a threshold of 1. This means that only one key is required to unseal the vault.
I deem this to be acceptable for personal use, but you might want to adjust this to your own needs.

```bash
vault operator init -key-shares=1 -key-threshold=1
```

if you are using a single key share and threshold of 1, the output will look like this:

```bash
Unseal Key 1: 

Initial Root Token: 
```
Store these secrets in a safe place.

## Configuring vault

We need to enable userpass for normal user authentication.

First unseal the vault using the key provided by the initialization step.

```bash
vault operator unseal
```
Then we need to login as root. Here the helper functions come in use.

```bash
vault_token_login
```

After this we can enable the userpass authentication method.

```bash
vault auth enable userpass
```
## Create the first user

Here again we take a shortcut. All users will have a default policy which gives them following rights to path /secrets/<username>
- create
- read
- list
- update
- delete

