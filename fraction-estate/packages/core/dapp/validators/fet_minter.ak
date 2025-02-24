//// The new FET minting contract handles the one-shot minting of the new 100M
//// FET and the burning of any FET at a later time. The new tokens will be 
//// sent to a wallet of the multsig choosing at the time of mint. The minting
//// action will simutaniously mint the 100M and the reference token. The
//// reference token must be sent to the storage contract with a valid cip 68
//// datum. The minting is a one-time process but burning can happen as long
//// as a valid multsig is present.
////

use aiken/bytearray
use aiken/transaction.{Input, Mint, OutputReference, ScriptContext, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use assist/addresses
use assist/data
use assist/find
use assist/minting
use assist/payout
use assist/signing
use assist/std
use assist/tx
use assist/types/cip68.{CIP68}
use assist/types/hashes.{TxHash, ValidatorHash}
use assist/values
use dapp/constants
use dapp/types/fet_minter.{BurnTokens, MintTokens, MinterRedeemer}
use dapp/types/reference.{ReferenceDatum}
use dapp/util

validator(
  // tx id and idx for one shot
  tx_id_hash: TxHash,
  tx_id_idx: Int,
  // genesis token information
  genesis_pid: PolicyId,
  genesis_tkn: AssetName,
  // data reference hash
  data_ref_hash: ValidatorHash,
) {
  fn params(redeemer: MinterRedeemer, context: ScriptContext) -> Bool {
    // must be minting
    expect Mint(currency_symbol) = context.purpose
    // the transaction being validated
    let Transaction {
      inputs,
      outputs,
      reference_inputs,
      extra_signatories,
      mint,
      datums,
      ..
    } = context.transaction
    // get reference data stuff
    let ref_addr: Address = credential.from_script(data_ref_hash)
    let ref_input: Input = find.input_by_addr(reference_inputs, ref_addr)
    expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
    // what is being minted in this transaction
    let mint_list: List<(PolicyId, AssetName, Int)> =
      mint
        |> value.from_minted_value()
        |> value.flatten()
    // catch the redeemer for minting or burning
    when redeemer is {
      // this happens once
      MintTokens -> {
        // use the ref prefix + token name
        let reference_tkn: AssetName =
          bytearray.concat(cip68.prefix_100, constants.new_fet_name)
        // use the ft prefix + token name
        let fungible_tkn: AssetName =
          bytearray.concat(cip68.prefix_333, constants.new_fet_name)
        // this output reference must be spent
        let this_out_ref: OutputReference = std.out_ref(tx_id_hash, tx_id_idx)
        // the storage address, may be staked
        let storage_addr: Address =
          addresses.create_script_address(
            ref_datum.storage,
            ref_datum.staking.vkh,
          )
        // this prevents bricking the utxo with the missing datum attack
        expect _: CIP68 = util.output_datum(outputs, storage_addr, datums)
        //
        // This minting endpoint can only happen once. It will send the 
        // reference token to the storage contract and allow the fungible
        // tokens to be sent anywhere the multisig wants.
        //
        and {
          // do an address check here for the storage contract
          and {
            // storage vkh must have valid length
            bytearray.length(ref_datum.storage) == 28,
            // the staking vkh is valid or empty
            or {
              bytearray.is_empty(ref_datum.staking.vkh),
              bytearray.length(ref_datum.staking.vkh) == 28,
            },
          }?,
          // at least the reference token must go to cip 68 storage contract
          payout.at_least(
            storage_addr,
            value.from_asset(currency_symbol, reference_tkn, 1),
            outputs,
          )?,
          // these inputs must be spending this output reference
          tx.is_spending_input(inputs, this_out_ref)?,
          // only keepers can update the data
          signing.verify_multisig(
            extra_signatories,
            ref_datum.keepers.pkhs,
            ref_datum.keepers.threshold,
          )?,
          // must mint 1 reference token
          minting.exact(mint_list, currency_symbol, reference_tkn, 1)?,
          // must mint 100 M fungible tokens with 10 decimal places
          minting.exact(
            mint_list,
            currency_symbol,
            fungible_tkn,
            1_000_000_000_000_000_000,
          )?,
          // data reference must be holding correct token
          values.prove_exact_nft(
            ref_input.output.value,
            genesis_pid,
            genesis_tkn,
          )?,
        }
      }
      // this can happen whenever, set burn_amt to zero when burning the ref token
      BurnTokens { burn_amt } -> and {
          // burn amount must be negative or zero
          (burn_amt <= 0)?,
          // has to be a multisig action
          signing.verify_multisig(
            extra_signatories,
            ref_datum.keepers.pkhs,
            ref_datum.keepers.threshold,
          )?,
          // one ref token or any amount of tokens or both
          or {
            // burn only 1 ref token
            minting.by_prefix(mint_list, currency_symbol, cip68.prefix_100, -1)?,
            // burn any amount of the fractions
            minting.by_prefix(
              mint_list,
              currency_symbol,
              cip68.prefix_333,
              burn_amt,
            )?,
          }?,
          // data reference must be holding correct token
          values.prove_exact_nft(
            ref_input.output.value,
            genesis_pid,
            genesis_tkn,
          )?,
        }
    }
  }
}