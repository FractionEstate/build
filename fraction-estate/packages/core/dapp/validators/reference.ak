//// This contract controls the updating of the reference data required for the
//// other contracts to function properly. It handles the staking data, the 
//// storage validator hash, and the multisig.
////

use aiken/transaction.{Input, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{Value}
use assist/count
use assist/find
use assist/payout
use assist/signing
use dapp/types/reference.{ReferenceDatum}

validator {
  fn params(
    this_datum: ReferenceDatum,
    _redeemer: Void,
    context: ScriptContext,
  ) -> Bool {
    // must be spending
    expect Spend(output_reference) = context.purpose
    // this tx being validated
    let Transaction { inputs, outputs, extra_signatories, .. } =
      context.transaction
    // the input being spent
    let this_input: Input = find.input_by_ref(inputs, output_reference)
    // this value being spent
    let this_value: Value = this_input.output.value
    // this address being spent from
    let this_addr: Address = this_input.output.address
    // that datum must have the ReferenceDatum Structure
    expect that_datum: ReferenceDatum =
      find.output_datum_by_addr(outputs, this_addr)
    // remove the lovelace so it can change naturally with datum updates
    let that_value: Value = this_value |> value.without_lovelace
    //
    // Only the keepers of the reference data can update the reference
    // data. The reference contract is genesis token agnostic so there
    // could be many genesis each with their own keepers. The storage
    // contract hash and the staking data are open to change but the data
    // must contain a valid keeper data structure.
    // 
    and {
      // only keepers can update the data
      signing.verify_multisig(
        extra_signatories,
        this_datum.keepers.pkhs,
        this_datum.keepers.threshold,
      )?,
      // send that value exactly back to this address.
      payout.at_least(this_addr, that_value, outputs)?,
      // single script input
      count.inputs_by_addr(inputs, this_addr, 1)?,
      // single script output
      count.outputs_by_addr(outputs, this_addr, 1)?,
      // the reference datum must have valid keepers
      reference.is_valid_keepers(that_datum.keepers)?,
    }
  }
}