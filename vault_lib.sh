# shellcheck shell=bash
function check_auth_status() { # Internal
# Validate authentication status. Checks environmental variables and does a 
# test login.

    if [[ -z "$VAULT_TOKEN" || -z "$VAULT_SECRET_PATH" ]]; then
        echo "You don't seem to be logged onto Vault." >&2
        return 1
    else
        if ! vault token lookup > /dev/null 2>&1; then
            echo -e "\nToken is incorrect, try again?"
            return 1
        fi
    fi
    return 0
}

function check_binary() { # Internal
# Validates if given binary/binaries exists on system. Returns 1 if not.
# Usage: check_binary vault

    final_result=0

    # shellcheck disable=SC2068 
    for binary in ${@}; do
        if ! hash "${binary}" 2>/dev/null; then 
            echo "Missing ${binary}" >&2
            final_result=1
        fi
    done

    return $final_result
}

# Note: other ways to create bcrypt in Raspbian turned out to be too complicated
# this is just easier. ref StackOverflow 307994
function bcrypt() {
# Create bcrypt hash using python3 and bcrypt package
# Usage: bcrypt

    if ! check_binary python3 pip; then return 1; fi
    if ! pip list | grep bcrypt > /dev/null; then 
        echo "Missing bcrypt package. pip install bcrypt?" >&2
        return 1;
    fi

    if BCRYPTED_PASSWORD=$(python3 -c "import bcrypt; import sys; \
        import getpass;password=getpass.getpass('Enter password:'); \
        print(bcrypt.hashpw(password.encode('utf-8'), \
        bcrypt.gensalt()).decode())");
    then
        echo "${BCRYPTED_PASSWORD}"
    else
        echo "Failed to generate bcrypt hash." >&2
        return 1
    fi
}

function vault_add_user() {
# Add user to default location /auth/userpass. Takes username as optional param.
# Usage: vault_add_user Username or vault_add_user

    local POLICY_LIST=()

    if ! check_binary vault python3; then return 1; fi
    if [ -z "${VAULT_TOKEN}" ]; then
        echo "You need to login"
        return 1;
    fi

    if [ -z "$1" ]; then
        read -rp "Enter username: " USERNAME
    else
        USERNAME="$1"
    fi

    if ! bcrypted_password=$(bcrypt); then
        echo "Password creation failed." >&2
        return 1;
    fi

    if ! vault policy list > /dev/null 2>&1 ; then 
        echo "Missing rights to list policies. Log in with higher rights?"
        return 1; 
    fi

    # shellcheck disable=SC2207
    POLICY_LIST=($(vault policy list))

    # Display the options to the user
    echo "Choose a policy:"
    select choice in "${POLICY_LIST[@]}"
    do
        vault write auth/userpass/users/"${USERNAME}" \
            password_hash="${bcrypted_password}" \
            policies="${choice}"
        break
    done

    # Create secrets path
    vault secrets enable -path "secrets/${USERNAME}"  kv-v2

}

function vault_delete_user(){
# Deletes provided user, all its secrets and its policy. Accepts -f as option 
# to not question deletion

    local FORCE=false
    local USER=''

    if [ -z "$1" ]; then
       echo "Usage: ${FUNCNAME[0]} <username> or" >&2
       echo "Usage: ${FUNCNAME[0]} <username> -f for removing without a prompt" >&2
       return 1
    fi

    if [ $# -gt 2 ]; then
       echo "Usage: ${FUNCNAME[0]} <username> or" >&2
       echo "Usage: ${FUNCNAME[0]} <username> -f for removing without a prompt" >&2
       return 1
    fi

    if ! check_auth_status; then vault_login;fi

    while [ "$#" -gt 0 ]; do
        case $1 in
            -f)
                FORCE=true
                ;;
            *)
                USER+="$1"
        esac
        shift
    done

    if [ "$FORCE" == true ]; then
        vault delete "auth/userpass/users/$USER"
        
    else
        # shellcheck disable=SC2145
        echo "This will also delete policies and secrets of user ${USER}."
        read -rp "Are you sure you want to delete ${USER}? (y/n): " ANSWER
        if [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]; then
            vault delete "auth/userpass/users/$USER"
        else
            echo "Not deleting user"
            return 0
        fi
    fi
    # Clean up after the user account, remove policies & secrets
    vault_delete_user_policy "${USER}"
    vault secrets disable "secrets/${USER}";
}

function vault_token_login() {
# Function to set environment token VAULT_TOKEN. Meant to be used with root user
# Does not set the correct values for secret retrieval

    if ! check_binary vault; then return 1; fi

    read -rsp "Enter Vault token: " VAULT_TOKEN
    if [ -z "${VAULT_TOKEN}" ]; then 
        echo "Token cannot be empty." >&2
        return 1
    fi

    export VAULT_TOKEN
    if ! vault token lookup > /dev/null 2>&1; then
        echo -e "\nToken is incorrect, try again?"
        return 1
    fi
}

# shellcheck disable=SC2120
function vault_login() {
# Login to vault with username & password. Uses VAULT_TOKEN to keep the session
# Usage: vault_login Username or vault_login

    local USERNAME=''

    if ! check_binary vault; then return 1; fi

    if [ -n "${1}" ]; then
        USERNAME=${1}
    else
        read -rp "Enter username: " USERNAME
    fi
    read -rsp "Enter password: " PASSWORD

    # Check if password is empty
    if [ -z "${PASSWORD}" ]; then 
        echo "Password cannot be empty." >&2
        return 1
    fi

    if ! VAULT_TOKEN=$(vault login -method=userpass -token-only\
        username="${USERNAME}" \
        password="${PASSWORD}");
    then 
        PASSWORD=''
        return 1; 
    fi

    VAULT_SECRET_PATH="secrets/${USERNAME}";
    export VAULT_SECRET_PATH
    export VAULT_TOKEN
        
    if check_auth_status; then 
        echo "" # "pretty print thing..."
    else
        unset VAULT_SECRET_PATH
        unset VAULT_TOKEN
        echo "Failed to login?" >&2
        return 1
    fi
}

function get_secret() {
# Prints the given secret. Hard coded to use field secret.

    if [ $# -ne 1 ]; then 
        echo "Usage: ${FUNCNAME[0]} <secret>" >&2
        return 1
    fi
    secret_field="${1}"

    if ! check_auth_status; then vault_login;fi

    if ! SECRET=$(vault kv get -mount="${VAULT_SECRET_PATH}" -field=secret "${secret_field}");then return 1; fi

    echo "${SECRET}"
}

function set_secret() {
# Stores secret to the path VAULT_SECRET_PATH/<secret> with a key secret

    if [ $# -ne 1 ]; then 
        echo "Usage: ${FUNCNAME[0]} <secretname>" >&2
        return 1
    fi

    if ! check_auth_status; then vault_login;fi

    read -rsp "Enter secret: " SECRET
    
    SECRET=$(trim "${SECRET}")

    if ! vault kv put -mount="${VAULT_SECRET_PATH}" "${1}" secret="${SECRET}";\
    then
        return 1
    fi
}

function list_secrets() {
# Lists secrets visible to the user in the VAULT_SECRET_PATH

    if ! check_auth_status; then vault_login;fi
    vault kv list -mount="${VAULT_SECRET_PATH}"
}

function delete_secret() {
# Delete given secret permanently. Accepts -f as option to not question deletion

    local FORCE=false
    local SECRET=''

    if [ -z "$1" ]; then
       echo "Usage: ${FUNCNAME[0]} <secret> or" >&2
       echo "Usage: ${FUNCNAME[0]} <secret> -f for removing without a prompt" >&2
       return 1
    fi

    if [ $# -gt 2 ]; then
       echo "Usage: ${FUNCNAME[0]} <secret> or" >&2
       echo "Usage: ${FUNCNAME[0]} <secret> -f for removing without a prompt" >&2
       return 1
    fi

    if ! check_auth_status; then vault_login;fi

    while [ "$#" -gt 0 ]; do
        case $1 in
            -f)
                FORCE=true
                ;;
            *)
                SECRET+="$1"
        esac
        shift
    done

    if [ "$FORCE" == true ]; then
        vault kv metadata delete "${VAULT_SECRET_PATH}/$SECRET"
    else
        # shellcheck disable=SC2145
        read -rp "Are you sure you want to delete ${SECRET}? (y/n): " ANSWER
        if [[ "$ANSWER" == "y" || "$ANSWER" == "Y" ]]; then
            vault kv metadata delete "${VAULT_SECRET_PATH}/$SECRET"
        else
            echo "Not deleting the secret"
            return 0
        fi
    fi
}

function trim() { # Internal
# Remove leading and trailing whitespace from string

# ref https://web.archive.org/web/20121022051228/http://codesnippets.joyent.com/posts/show/1816

    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

function vault_add_user_policy() {
# Adds new policy for a user, which has create, read, list, update and delete
# rights to secrets/USERNAME/* path. Accepts username as argument.

    read -r -d '' POLICY_TEMPLATE <<- EOF
path "secrets/USERNAME/*" { 
  capabilities = ["create", "read", "update", "delete", "list"] 
}
EOF

    if [ $# -ne 1 ]; then 
        echo "Usage: ${FUNCNAME[0]} <username>"  >&2
        return 1
    fi

    TMP_POLICY=$(mktemp)
    echo "${POLICY_TEMPLATE//USERNAME/$1}" > "$TMP_POLICY"
    echo "Will write policy $(cat "$TMP_POLICY") to vault."

    vault policy write "$1" "$TMP_POLICY" || {
        echo "Failed to create the policy for user $1. Login as root \
(vault_token_login)?" >&2; rm "$TMP_POLICY"; return 1; }
    rm "$TMP_POLICY"
}

function vault_delete_user_policy() {
# Deletes user policy from Vault. Accepts username as argument

    if [ $# -ne 1 ]; then 
        echo "Usage: ${FUNCNAME[0]} <username>"   >&2
        return 1
    fi

    vault policy delete "$1" || { echo "Failed to delete the policy for user $1. \
Login as root (vault_token_login)?" >&2; return 1; }
}

function get_help() {
# Lists my custom functions and their help descriptions. Ignores internal
# functions. Help is the two lines after the function name.
  local CHOISES=()
  function_directories=("${HOME}/.local/lib/juha" "${HOME}/.local/lib/work")

  for directory in "${function_directories[@]}"; do
    if [ -d "$directory" ]; then
      for item in "$directory"/*.sh; do
        CHOISES+=("${item##*/}")
      done
    fi
  done

  CHOISES+=("all")
  echo "Choose:"
  select choice in "${CHOISES[@]}"
  do
    if [ "$choice" == 'all' ] ; then choice='*'; fi
    for directory in "${function_directories[@]}"; do
      if [ -d "$directory" ]; then
      # shellcheck disable=SC2086
        if [ -f "$directory/"$choice ]; then
          grep -vi '# internal' "$directory/"$choice | \
          grep -A 2 -h '^function' | \
          sed 's/#/  /g; s/^function //g; s/() {//g'
        fi
      fi
    done
    break
  done

}