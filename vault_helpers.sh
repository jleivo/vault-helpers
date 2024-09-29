#!/bin/bash

# Check if VAULT_TOKEN and VAULT_SECRET_PATH are defined
# if not, exit with error code 1
check_auth_status() {

    if [ -z "${VAULT_TOKEN}" ] && [ -z "${VAULT_SECRET_PATH}" ]; then
        echo "You don't seem to be logged onto Vault." >&2
        return 1
    fi
    return 0

}

# General purpose function to check if binary is installed
check_binary() {

    final_result=0

    # shellcheck disable=SC2068 
    for binary in ${@}; do
        if ! hash "${binary}" 2>/dev/null; then 
            echo "Missing ${binary}"
            final_result=1
        fi
    done

    return $final_result
    
}

# a function that uses python to create bcrypt hash
# as other ways to create bcrypt in Raspbian turned out to be too complicated
# this is just easier. ref StackExchange 307994
bcrypt() {
    if ! check_binary python3; then return 1; fi

    if bcrypted_password=$(python3 -c "import bcrypt; import sys; \
        print(bcrypt.hashpw(sys.argv[1].encode('utf-8'), \
        bcrypt.gensalt()).decode())" "${@}");
    then
        echo "${bcrypted_password}"
    else
        echo "Failed to generate bcrypt hash." >&2
        return 1
    fi
}

# add new user to vault default userpass location /auth/userpass
# requests user password and encrypts it with bcrypt
vault_add_user() {

    if ! check_binary vault python3; then return 1; fi

    read -rp "Enter username: " USERNAME
    read -rsp "Enter password: " PASSWORD

    # Check if password is empty
    if [ -z "${PASSWORD}" ]; then 
        echo "Password cannot be empty." >&2
        return 1
    fi

    bcrypted_password=$(bcrypt "${PASSWORD}")

    # shellcheck disable=SC2207
    if ! policy_list=($(vault policy list));then return 1; fi

    # Display the options to the user
    echo "Choose a policy:"
    select choice in "${policy_list[@]}"
    do
        vault write auth/userpass/users/"${USERNAME}" \
            password_hash="${bcrypted_password}" \
            policies="${choice}"
        break
    done

}

vault_token_login(){

    if ! check_binary vault; then return 1; fi

    read -rsp "Enter Vault token: " VAULT_TOKEN
    if [ -z "${VAULT_TOKEN}" ]; then 
        echo "Token cannot be empty." >&2
        return 1
    fi

    export VAULT_TOKEN

}

# login to vault with user and password to get the token 
# and export it to environment variable
# can take username as argument
# shellcheck disable=SC2120
vault_login(){

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
    then return 1; fi

        
    if [ -z "${VAULT_TOKEN}" ]; then 
        echo "Failed to login?" >&2
        return 1
    fi

    VAULT_SECRET_PATH="secrets/${USERNAME}";
    export VAULT_SECRET_PATH
    export VAULT_TOKEN

}

# check that VAULT_TOKEN and VAULT_SECRET_PATH are set
# if not, forces logon
# expects that secrets are stored using the set_secrets function
get_secret(){

    if [ $# -ne 1 ]; then 
        echo "Usage: ${FUNCNAME[0]} <secret>" >&2
        return 1
    fi
    secret_field="${1}"

    if ! check_auth_status; then vault_login;fi

    if ! SECRET=$(vault kv get -mount="${VAULT_SECRET_PATH}" -field=secret "${secret_field}");then return 1; fi

    echo "${SECRET}"
}

# check that VAULT_TOKEN and VAULT_SECRET_PATH are set
# if not, forces logon
# Stores secret to the path VAULT_SECRET_PATH/<secret> with a key secret
set_secret(){

    if [ $# -ne 1 ]; then 
        echo "Usage: ${FUNCNAME[0]} <secret>" >&2
        return 1
    fi

    if ! check_auth_status; then vault_login;fi

    read -rsp "Enter secret: " SECRET

    if ! vault kv put -mount="${VAULT_SECRET_PATH}" "${1}" secret="${SECRET}";then return 1; fi
}

list_secrets(){
    if ! check_auth_status; then vault_login;fi
    vault kv list -mount="${VAULT_SECRET_PATH}"
}