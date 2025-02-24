#!/bin/bash
set -e

# return the value of that file or echo the empty string
function cat_file_or_empty() {
  if [ -e "$1" ]; then
    cat "$1"
  else
    echo ""
  fi
}

# create directories if dont exist
mkdir -p contracts
mkdir -p hashes
mkdir -p certs

# remove old files
rm contracts/* || true
rm hashes/* || true
rm certs/* || true
rm -fr build/ || true

# Build, Apply, Convert
echo -e "\033[1;34m Building Contracts \033[0m"

# remove all traces for production
# aiken build --trace-level silent --filter-traces user-defined

# keep the traces for testing
aiken build --trace-level verbose --filter-traces all

echo -e "\033[1;33m\nBuilding Reference Data Contract \033[0m"
aiken blueprint convert -v reference.params > contracts/reference_contract.plutus
cardano-cli transaction policyid --script-file contracts/reference_contract.plutus > hashes/reference_contract.hash
echo -e "\033[1;33m Reference Data Contract Hash: $(cat hashes/reference_contract.hash) \033[0m"

# reference contract hash
ref_hash=$(cat hashes/reference_contract.hash)
ref_hash_cbor=$(python3 -c "import cbor2;hex_string='${ref_hash}';data=bytes.fromhex(hex_string);encoded=cbor2.dumps(data);print(encoded.hex())")

# genesis tx id#idx
genesis_tx_id=$(jq -r '.genesis_tx_id' compile_info.json)
genesis_tx_idx=$(jq -r '.genesis_tx_idx' compile_info.json)
genesis_tx_id_cbor=$(python3 -c "import cbor2;hex_string='${genesis_tx_id}';data=bytes.fromhex(hex_string);encoded=cbor2.dumps(data);print(encoded.hex())")
genesis_tx_idx_cbor=$(python3 -c "import cbor2;encoded=cbor2.dumps(${genesis_tx_idx});print(encoded.hex())")

# old fet token information
fet_pid=$(jq -r '.fet_pid' compile_info.json)
fet_tkn=$(jq -r '.fet_tkn' compile_info.json)
fet_pid_cbor=$(python3 -c "import cbor2;hex_string='${fet_pid}';data=bytes.fromhex(hex_string);encoded=cbor2.dumps(data);print(encoded.hex())")
fet_tkn_cbor=$(python3 -c "import cbor2;hex_string='${fet_tkn}';data=bytes.fromhex(hex_string);encoded=cbor2.dumps(data);print(encoded.hex())")

echo -e "\033[1;33m\nBuilding Genesis Contract \033[0m"
aiken blueprint apply -o plutus.json -v genesis.params "${genesis_tx_id_cbor}"
aiken blueprint apply -o plutus.json -v genesis.params "${genesis_tx_idx_cbor}"
aiken blueprint apply -o plutus.json -v genesis.params "${ref_hash_cbor}"
aiken blueprint apply -o plutus.json -v genesis.params "${fet_pid_cbor}"
aiken blueprint apply -o plutus.json -v genesis.params "${fet_tkn_cbor}"
aiken blueprint convert -v genesis.params > contracts/genesis_contract.plutus
cardano-cli transaction policyid --script-file contracts/genesis_contract.plutus > hashes/genesis_contract.hash
echo -e "\033[1;33m Genesis Contract Hash: $(cat hashes/genesis_contract.hash) \033[0m"

# the pointer token
genesis_prefix="ca11ab1e"
genesis_pid=$(cat hashes/genesis_contract.hash)
full_genesis_tkn="${genesis_prefix}${genesis_tx_idx_cbor}${genesis_tx_id}"
genesis_tkn="${full_genesis_tkn:0:64}"
echo -e "\033[1;36m\nGenesis Token: 1 ${genesis_pid}.${genesis_tkn} \033[0m"

# one liner for correct cbor
genesis_pid_cbor=$(python3 -c "import cbor2;hex_string='${genesis_pid}';data=bytes.fromhex(hex_string);encoded=cbor2.dumps(data);print(encoded.hex())")
genesis_tkn_cbor=$(python3 -c "import cbor2;hex_string='${genesis_tkn}';data=bytes.fromhex(hex_string);encoded=cbor2.dumps(data);print(encoded.hex())")

pool_id=$(jq -r '.pool_id' compile_info.json)

echo -e "\033[1;33m\nBuilding Staking Contract \033[0m"
aiken blueprint apply -o plutus.json -v staking.params "${genesis_pid_cbor}"
aiken blueprint apply -o plutus.json -v staking.params "${genesis_tkn_cbor}"
aiken blueprint apply -o plutus.json -v staking.params "${ref_hash_cbor}"
aiken blueprint convert -v staking.params > contracts/staking_contract.plutus
cardano-cli transaction policyid --script-file contracts/staking_contract.plutus > hashes/staking_contract.hash
cardano-cli stake-address registration-certificate --stake-script-file contracts/staking_contract.plutus --out-file certs/registration.cert
cardano-cli stake-address delegation-certificate --stake-script-file contracts/staking_contract.plutus --stake-pool-id ${pool_id} --out-file certs/delegation.cert
echo -e "\033[1;33m Staking Contract Hash: $(cat hashes/staking_contract.hash) \033[0m"

echo -e "\033[1;33m\nBuilding Storage Contract \033[0m"
aiken blueprint apply -o plutus.json -v storage.params "${genesis_pid_cbor}"
aiken blueprint apply -o plutus.json -v storage.params "${genesis_tkn_cbor}"
aiken blueprint apply -o plutus.json -v storage.params "${ref_hash_cbor}"
aiken blueprint convert -v storage.params > contracts/storage_contract.plutus
cardano-cli transaction policyid --script-file contracts/storage_contract.plutus > hashes/storage_contract.hash
echo -e "\033[1;33m Storage Contract Hash: $(cat hashes/storage_contract.hash) \033[0m"

# fet minter tx id#idx
fet_minter_tx_id=$(jq -r '.fet_minter_tx_id' compile_info.json)
fet_minter_tx_idx=$(jq -r '.fet_minter_tx_idx' compile_info.json)
fet_minter_tx_id_cbor=$(python3 -c "import cbor2;hex_string='${fet_minter_tx_id}';data=bytes.fromhex(hex_string);encoded=cbor2.dumps(data);print(encoded.hex())")
fet_minter_tx_idx_cbor=$(python3 -c "import cbor2;encoded=cbor2.dumps(${fet_minter_tx_idx});print(encoded.hex())")

echo -e "\033[1;33m\nBuilding FET Minter Contract \033[0m"
aiken blueprint apply -o plutus.json -v fet_minter.params "${fet_minter_tx_id_cbor}"
aiken blueprint apply -o plutus.json -v fet_minter.params "${fet_minter_tx_idx_cbor}"
aiken blueprint apply -o plutus.json -v fet_minter.params "${genesis_pid_cbor}"
aiken blueprint apply -o plutus.json -v fet_minter.params "${genesis_tkn_cbor}"
aiken blueprint apply -o plutus.json -v fet_minter.params "${ref_hash_cbor}"
aiken blueprint convert -v fet_minter.params > contracts/fet_minter_contract.plutus
cardano-cli transaction policyid --script-file contracts/fet_minter_contract.plutus > hashes/fet_minter_contract.hash
echo -e "\033[1;33m FET Minter Contract Hash: $(cat hashes/fet_minter_contract.hash) \033[0m"

echo -e "\033[1;33m\nBuilding Queue Contract \033[0m"
aiken blueprint apply -o plutus.json -v queue.params "${genesis_pid_cbor}"
aiken blueprint apply -o plutus.json -v queue.params "${genesis_tkn_cbor}"
aiken blueprint apply -o plutus.json -v queue.params "${ref_hash_cbor}"
aiken blueprint convert -v queue.params > contracts/queue_contract.plutus
cardano-cli transaction policyid --script-file contracts/queue_contract.plutus > hashes/queue_contract.hash
echo -e "\033[1;33m Queue Contract Hash: $(cat hashes/queue_contract.hash) \033[0m"

echo -e "\033[1;33m\nBuilding RFT Minter Contract \033[0m"
aiken blueprint apply -o plutus.json -v rft_minter.params "${genesis_pid_cbor}"
aiken blueprint apply -o plutus.json -v rft_minter.params "${genesis_tkn_cbor}"
aiken blueprint apply -o plutus.json -v rft_minter.params "${ref_hash_cbor}"
aiken blueprint convert -v rft_minter.params > contracts/rft_minter_contract.plutus
cardano-cli transaction policyid --script-file contracts/rft_minter_contract.plutus > hashes/rft_minter_contract.hash
echo -e "\033[1;33m RFT Minter Contract Hash: $(cat hashes/rft_minter_contract.hash) \033[0m"

###############################################################################
############## DATUM AND REDEEMER STUFF #######################################
###############################################################################
echo -e "\033[1;33m Updating Reference Datum \033[0m"
# keepers
pkh1=$(cat_file_or_empty ./scripts/wallets/keeper-1-wallet/payment.hash)
pkh2=$(cat_file_or_empty ./scripts/wallets/keeper-2-wallet/payment.hash)
pkh3=$(cat_file_or_empty ./scripts/wallets/keeper-3-wallet/payment.hash)
pkhs="[{\"bytes\": \"$pkh1\"}, {\"bytes\": \"$pkh2\"}, {\"bytes\": \"$pkh3\"}]"
thres=2
# storage hash
storage_hash=$(cat hashes/storage_contract.hash)

# queue hash
queue_hash=$(cat hashes/queue_contract.hash)

# rft minting policy
rft_minting_pid=$(cat hashes/rft_minter_contract.hash)

# pool stuff
staking_hash=$(cat hashes/staking_contract.hash)
rewardPkh=$(cat_file_or_empty ./scripts/wallets/reward-wallet/payment.hash)
rewardSc=""

# update reference data
jq \
--argjson pkhs "$pkhs" \
--argjson thres "$thres" \
--arg storage "$storage_hash" \
--arg queue "$queue_hash" \
--arg staking "$staking_hash" \
--arg poolId "$pool_id" \
--arg rewardPkh "$rewardPkh" \
--arg rewardSc "$rewardSc" \
--arg policy_id "$rft_minting_pid" \
'.fields[0].fields[0].list |= ($pkhs | .[0:length]) | 
.fields[0].fields[1].int=$thres | 
.fields[1].bytes=$storage |
.fields[2].bytes=$queue |
.fields[3].fields[0].bytes=$staking |
.fields[3].fields[1].bytes=$poolId |
.fields[4].fields[0].bytes=$rewardPkh |
.fields[4].fields[1].bytes=$rewardSc |
.fields[5].bytes=$policy_id
' \
./scripts/data/genesis/genesis-datum.json | sponge ./scripts/data/genesis/genesis-datum.json

# Update Staking Redeemer
echo -e "\033[1;33m Updating Stake Redeemer \033[0m"

jq \
--arg stakeHash "$staking_hash" \
'.fields[0].fields[0].bytes=$stakeHash' \
./scripts/data/staking/delegate-redeemer.json | sponge ./scripts/data/staking/delegate-redeemer.json

# end of build
echo -e "\033[1;32m\nBuilding Complete! \033[0m"