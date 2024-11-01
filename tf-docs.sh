#!/bin/bash -e

tfproviders=(
    "azuread:60958"
    "azurerm:61820"
    "helm:61379"
    "http:59770"
    "kubectl:61545" # alekc/kubectl
    "kubernetes:61209"
    "local:59855"
    "null:59862"
    "random:59857"
    "tls:59867"
    )

baseUrl="https://registry.terraform.io/v2"
mkdir -p ./terraform_azure_docs

for item in "${tfproviders[@]}"; do
    providerShortName="${item%%:*}"
    providerId="${item#*:}"
    providerUrl="${baseUrl}/provider-versions/${providerId}?include=provider-docs"

    wget -q -O - "$providerUrl" | jq -r > ./terraform_azure_docs/"${providerShortName}"
    if [[ "kubectl" == "$providerShortName" ]]; then
        providerFullName="$providerShortName"
    else
        providerFullName="$(jq -r '.data.attributes.description' ./terraform_azure_docs/"${providerShortName}")"
    fi
    providerVersion="$(jq -r '.data.attributes.version' ./terraform_azure_docs/"${providerShortName}")"
    documentPaths="$(jq -r '.included[].links.self' ./terraform_azure_docs/"${providerShortName}" | sort)"
    totalDocumentCount="$(echo "$documentPaths" | wc -l)"
    currentPage="$(echo "$documentPaths" | head -n 1 | awk -F "/" '{print $4}')"
    lastPage="$(echo "$documentPaths" | tail -n 1 | awk -F "/" '{print $4}')"
    rm ./terraform_azure_docs/"${providerShortName}"
    targetDir="./terraform_azure_docs/${providerFullName}_${providerVersion}"
    mkdir -p "$targetDir"
    fetching=1
    echo ""

    while [[ $currentPage -le $lastPage ]]; do
        echo "Fetching documentation of ${providerFullName} v${providerVersion}, ${fetching}/${totalDocumentCount}"
        wget -q -O - "${baseUrl}/provider-docs/${currentPage}" | jq '.data.attributes' > "$targetDir"/temp
        category="$(jq -r '.category' "$targetDir"/temp)"
        title="$(jq -r '.title' "$targetDir"/temp | sed 's/:/ -/g')"
        jq -r '.content' "$targetDir"/temp > "$targetDir"/output
        sed -i -e 's/"---//g' -e 's/\\n"//g' -e 's/\\"/\"/g' -e 's/\\n/\n/g' -e 's/```hcl/\n```hcl/g' -e 's/```##/\n```##\n/g' "$targetDir"/output
        mv "$targetDir"/output "$targetDir"/"${category}_${title}".md
        if [[ "$(grep -c "$providerShortName" "$targetDir"/"${category}_${title}".md)" -eq 0 ]]; then
            echo "Downloaded document (\"${category}_${title}.md\") does not belong in the \"${providerFullName}\" provider."
            echo "Page url: ${baseUrl}/provider-docs/${currentPage}."
            rm "$targetDir"/"${category}_${title}".md
        fi
        rm "$targetDir"/temp
        fetching="$((fetching + 1))"
        currentPage="$((currentPage + 1))"
    done
done