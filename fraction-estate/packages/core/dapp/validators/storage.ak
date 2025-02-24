//// This contracts handles any and all cip 68 metadatum storage logic. A
//// metadatum can be updated or removed. Removing does not require a burn as
//// that endpoint can be used in the event ofa contract forking event. The
//// update endpoint requires the reference token to be sent back to the 
//// contract and it must contain a valid multisig data structure.
////

use aiken/transaction.{Input, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId, Value}
use assist/count
use assist/data
use assist/find
use assist/payout
use assist/signing
use assist/types/cip68.{CIP68}
use assist/types/hashes.{ValidatorHash}
use assist/values
use dapp/types/reference.{ReferenceDatum}
use dapp/types/storage.{RemoveMetadatum, StorageRedeemer, UpdateMetadatum}
use dapp/util

validator(
  // genesis token information
  genesis_pid: PolicyId,
  genesis_tkn: AssetName,
  // data reference hash
  data_ref_hash: ValidatorHash,
) {
  fn params(
    _datum: CIP68,
    redeemer: StorageRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(output_reference) = context.purpose
    when redeemer is {
      // removes the utxo entirely from the contract
      RemoveMetadatum -> {
        // the transaction being validated
        let Transaction { inputs, reference_inputs, extra_signatories, .. } =
          context.transaction
        // get reference data stuff
        let ref_addr: Address = credential.from_script(data_ref_hash)
        let ref_input: Input = find.input_by_addr(reference_inputs, ref_addr)
        expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
        // this input is being validated
        let this_input: Input = find.input_by_ref(inputs, output_reference)
        // this script address
        let this_addr: Address = this_input.output.address
        //
        // A valid multisig can remove a single metadatum UTxO from the 
        // storage contract. This does not burn any tokens as the reference
        // tokens may just need to be moved.
        //
        and {
          // only keepers can update the data
          signing.verify_multisig(
            extra_signatories,
            ref_datum.keepers.pkhs,
            ref_datum.keepers.threshold,
          )?,
          // single script input, no output count check required
          count.inputs_by_addr(inputs, this_addr, 1)?,
          // must be the correct reference data
          values.prove_exact_nft(
            ref_input.output.value,
            genesis_pid,
            genesis_tkn,
          )?,
        }
      }
      // updates the metadata and can change the minimum lovelace
      UpdateMetadatum -> {
        let Transaction {
          inputs,
          outputs,
          reference_inputs,
          extra_signatories,
          datums,
          ..
        } = context.transaction
        // get reference data stuff
        let ref_addr: Address = credential.from_script(data_ref_hash)
        let ref_input: Input = find.input_by_addr(reference_inputs, ref_addr)
        expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
        // this input is being validated
        let this_input: Input = find.input_by_ref(inputs, output_reference)
        // this script address
        let this_addr: Address = this_input.output.address
        // that value going back to the contract
        let that_value: Value =
          this_input.output.value |> value.without_lovelace
        // this prevents bricking the utxo with the empty datum attack
        expect _: CIP68 = util.output_datum(outputs, this_addr, datums)
        //
        // A valid mutlsig can update the metadatum. A single UTxO can be spent
        // and it must return back to the storage contract. The endpoint is
        // designed to allow the required lovelace to change naturally with
        // metadatum updates.
        //
        and {
          // send exactly that value to this address
          payout.at_least(this_addr, that_value, outputs)?,
          // only keepers can update the data
          signing.verify_multisig(
            extra_signatories,
            ref_datum.keepers.pkhs,
            ref_datum.keepers.threshold,
          )?,
          // single script input
          count.inputs_by_addr(inputs, this_addr, 1)?,
          // single script output
          count.outputs_by_addr(outputs, this_addr, 1)?,
          // must be the correct reference data
          values.prove_exact_nft(
            ref_input.output.value,
            genesis_pid,
            genesis_tkn,
          )?,
        }
      }
    }
  }
}