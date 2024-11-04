#!/bin/bash -e

tfproviders=(
    azuread:60958
    azurerm:61820
    helm:61379
    http:59770
    kubectl:61545 # alekc/kubectl
    kubernetes:61209
    local:59855
    null:59862
    random:59857
    tls:59867
)

baseUrl="https://registry.terraform.io/v2"
mkdir -p ./terraform_azure_docs

download_docs() {
    local providerShortName="$1"
    local providerId="$2"

    providerUrl="${baseUrl}/provider-versions/${providerId}?include=provider-docs"
    wget -q -O - "$providerUrl" | jq -r > ./terraform_azure_docs/"$providerShortName"

    if [[ "kubectl" == "$providerShortName" ]]; then
        providerFullName="$providerShortName"
    else
        providerFullName="$(jq -r '.data.attributes.description' ./terraform_azure_docs/"$providerShortName")"
    fi

    providerVersion="$(jq -r '.data.attributes.version' ./terraform_azure_docs/"$providerShortName")"
    documentPaths="$(jq -r '.included[].links.self' ./terraform_azure_docs/"$providerShortName" | sort)"
    totalDocumentCount="$(echo "$documentPaths" | wc -l)"
    currentPage="$(echo "$documentPaths" | head -n 1 | awk -F "/" '{print $4}')"
    lastPage="$(echo "$documentPaths" | tail -n 1 | awk -F "/" '{print $4}')"
    rm ./terraform_azure_docs/"$providerShortName"
    targetDir="./terraform_azure_docs/${providerFullName}_$providerVersion"
    mkdir -p "$targetDir"
    fetching=1

    while [[ $currentPage -le $lastPage ]]; do
        echo "Fetching documentation of $providerFullName v${providerVersion}, ${fetching}/$totalDocumentCount"
        response="$(curl -4 --retry 3 --retry-connrefused --retry-delay 20 --max-time 60 -s -S -w "%{http_code}" -o - "${baseUrl}"/provider-docs/"$currentPage")"
        http_status="${response: -3}"
        response_body="${response:0:${#response}-3}"

        if [[ "$http_status" -eq 429 ]]; then
            echo "Received HTTP 429, too many requests. Retrying after 1 minute delay..."
            sleep 60
            continue
        elif [[ "$http_status" -ne 200 ]]; then
            echo "Error fetching page $currentPage: HTTP status $http_status"
            break
        else
            echo "$response_body" | jq '.data.attributes' > "$targetDir/${currentPage}.tmp" &
        fi

        fetching="$((fetching + 1))"
        currentPage="$((currentPage + 1))"
    done
    wait

    for tempfile in "$targetDir"/*.tmp; do
        category="$(jq -r '.category' "$tempfile")"
        title="$(jq -r '.title' "$tempfile" | sed -e 's/[:`]//g' -e 's/ /_/g')"
        if [[ "$title" == "$category" ]]; then title="$providerShortName"; fi
        if [[ "$(grep -vc "$providerShortName" "$tempfile")" -eq 0 ]]; then
            echo "Downloaded document (\"${category}_${title}.md\") does not belong in the \"$providerFullName\" provider."
            echo "Page url: ${baseUrl}/provider-docs/${currentPage}."
        else
            jq -r '.content' "$tempfile" | sed -e 's/"---//g' -e 's/\\n"//g' -e 's/\\"/\"/g' -e 's/\\n/\n/g' -e 's/```hcl/\n```hcl/g' -e 's/```##/\n```##\n/g' > "$targetDir"/"${category}_$title".md
        fi
        rm "$tempfile"
    done
}

export -f download_docs
export baseUrl

for item in "${tfproviders[@]}"; do
    providerShortName="${item%%:*}"
    providerId="${item#*:}"
    download_docs "$providerShortName" "$providerId" &
done

wait
echo "All downloads completed."
