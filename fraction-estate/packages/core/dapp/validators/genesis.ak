//// Genesis mints a token into the reference data contract. This token is used
//// to prove that the reference data is the correct. To start genesis, 100M
//// old FET will be placed in a UTxO that will be spent and burned inside
//// the transaction. This will allow the genesis token to be minted.
////

use aiken/transaction.{Mint, OutputReference, ScriptContext, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use assist/find
use assist/minting
use assist/payout
use assist/prefixes
use assist/std
use assist/tx
use assist/types/hashes.{TxHash, ValidatorHash}
use dapp/types/reference.{ReferenceDatum}
use dapp/util

validator(
  // tx id and idx for one shot
  tx_id_hash: TxHash,
  tx_id_idx: Int,
  // data reference hash
  data_ref_hash: ValidatorHash,
  // old fet information
  fet_pid: PolicyId,
  fet_tkn: AssetName,
) {
  fn params(_redeemer: Void, context: ScriptContext) -> Bool {
    // must be minting
    expect Mint(currency_symbol) = context.purpose
    // destruct the tx with required fields
    let Transaction { inputs, outputs, mint, .. } = context.transaction
    // what is being minted in this transaction
    let mint_list: List<(PolicyId, AssetName, Int)> =
      mint
        |> value.from_minted_value()
        |> value.flatten()
    // create a one shot callable token name
    let token_name: AssetName =
      util.token_name(tx_id_hash, tx_id_idx, prefixes.callable)
    // this output reference must be spent
    let this_out_ref: OutputReference = std.out_ref(tx_id_hash, tx_id_idx)
    // get reference data stuff
    let data_ref_addr: Address = credential.from_script(data_ref_hash)
    // get the reference data datum by searching for an output with the nft
    expect reference_datum: ReferenceDatum =
      find.output_datum_by_nft(outputs, currency_symbol, token_name)
    //
    // The reference datum must have valid keepers upon entry. If not then
    // the UTxO would be bricked since the reference data contract is 
    // controlled by that multisig. The storage contract hash does not have to
    // be defined at genesis nor does the staking information.
    //
    and {
      // the reference datum must have valid keepers
      reference.is_valid_keepers(reference_datum.keepers)?,
      // must send to the data reference address
      payout.at_least(
        data_ref_addr,
        value.from_asset(currency_symbol, token_name, 1),
        outputs,
      )?,
      // these inputs must be spending this output reference
      tx.is_spending_input(inputs, this_out_ref)?,
      // mint exactly 1 pointer token
      minting.exact(mint_list, currency_symbol, token_name, 1)?,
      // burn 100M old fet with 10 decimal places
      // 100,000,000.0000000000, 1 with 18 zeros
      minting.exact(mint_list, fet_pid, fet_tkn, -1_000_000_000_000_000_000)?,
    }
  }
}