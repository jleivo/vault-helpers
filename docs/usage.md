# Using vault helpers

There are four basic operations related to secrets that you can perform with Vault:

- `set_secret` to create a secret.
- `get_secret` to read a secret.
- `delete_secret` to delete a secret.
- `list_secrets` to list all secrets in the personal path of the user.

## Set Secret

This is a wrapper to vault kv put command. It takes a single value, the name of the secret as input from command line and prompts for the secret. The secret is then stored at the personal path of the user with a hardcoded key of `secret`.

```bash
$ set_secret openai-api-key
Enter secret: ========== Secret Path ==========
secrets/juha/data/openai-api-key

======= Metadata =======
Key                Value
---                -----
created_time       2024-10-09T18:54:25.781227102Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```

## Get Secret

This is a wrapper to vault kv get command. It takes a single value, the name of the secret as input from command line and prints the secret.

```bash
$ get_secret openai-api-key
sk-fake-key-1234567890
```
## Delete Secret

This is a wrapper to vault kv delete command. It takes a single value, the name of the secret as input from command line and deletes the secret. Optionally -f can be used to skip confirmation.

```bash
$ delete_secret openai-api-key
Are you sure you want to delete openai-api-key? (y/n): y
Success! Data deleted (if it existed) at: secrets/juha/metadata/openai-api-key
```
## List Secrets

This is a wrapper to vault list command. It lists all secrets in the personal path of the user.

```bash 
$ list_secrets
openai-api-key
```

## Get help

This lists all the command and their very small documentation

```bash
get_help
```