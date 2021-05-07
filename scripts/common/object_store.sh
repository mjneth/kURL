
function object_store_exists() {
    if [ -n "$OBJECT_STORE_ACCESS_KEY" ] && \
        [ -n "$OBJECT_STORE_SECRET_KEY" ] && \
        [ -n "$OBJECT_STORE_CLUSTER_IP" ]; then
        return 0
    else
        return 1
    fi
}

function object_store_create_bucket() {
    if object_store_bucket_exists "$1" ; then
        echo "object store bucket $1 exists"
        return 0
    fi
    if ! _object_store_create_bucket "$1" ; then
        if object_store_exists; then
          return 1
        fi
        bail "attempted to create bucket $1 but no object store configured"
    fi
    echo "object store bucket $1 created"
}

function _object_store_create_bucket() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="PUT\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl -fsSL -X PUT  \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$bucket" >/dev/null 2>&1
}

function object_store_bucket_exists() {
    local bucket=$1
    local acl="x-amz-acl:private"
    local d=$(LC_TIME="en_US.UTF-8" TZ="UTC" date +"%a, %d %b %Y %T %z")
    local string="HEAD\n\n\n${d}\n${acl}\n/$bucket"
    local sig=$(echo -en "${string}" | openssl sha1 -hmac "${OBJECT_STORE_SECRET_KEY}" -binary | base64)

    curl -fsSL -I \
        --noproxy "*" \
        -H "Host: $OBJECT_STORE_CLUSTER_IP" \
        -H "Date: $d" \
        -H "$acl" \
        -H "Authorization: AWS $OBJECT_STORE_ACCESS_KEY:$sig" \
        "http://$OBJECT_STORE_CLUSTER_IP/$bucket" >/dev/null 2>&1
}
