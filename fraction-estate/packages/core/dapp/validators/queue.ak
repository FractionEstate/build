//// The queue contract acts as a staging position for clients wishing to use
//// Fraction Estate rich fungible token minting as a service. Fraction Estate
//// can use the contract for free but it is designed for other companies.
//// The queue entry holds the proposed metadatum, the payment, the mint
//// amount, and the company's multisig. A queue entry may be updated and 
//// removed at any time via a successful company multsig. This should allow
//// for edits to the metadatum and payment as required by Fraction Estate.
//// The act of processing the queue entry is automated so companies are
//// expected to provide a single tx worth of gas for this action.
////

use aiken/list
use aiken/transaction.{Input, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId, Value}
use assist/addresses
use assist/count
use assist/data
use assist/find
use assist/minting
use assist/payout
use assist/signing
use assist/types/cip68.{CIP68}
use assist/types/hashes.{ValidatorHash}
use assist/values
use dapp/types/queue.{
  ProcessEntry, QueueDatum, QueueRedeemer, RemoveEntry, UpdateEntry,
}
use dapp/types/reference.{ReferenceDatum}
use dapp/util

validator(
  // genesis token information
  genesis_pid: PolicyId,
  genesis_tkn: AssetName,
  // data reference hash
  data_ref_hash: ValidatorHash,
) {
  fn params(
    this_datum: QueueDatum,
    redeemer: QueueRedeemer,
    context: ScriptContext,
  ) -> Bool {
    expect Spend(output_reference) = context.purpose
    when redeemer is {
      // removes the utxo entirely from the contract
      RemoveEntry -> {
        // the transaction being validated
        let Transaction { inputs, outputs, extra_signatories, .. } =
          context.transaction
        // this input is being validated
        let this_input: Input = find.input_by_ref(inputs, output_reference)
        // this script address
        let this_addr: Address = this_input.output.address
        //
        // A valid multisig from the owners of the queue entry may remove
        // the UTxO to any destination but the queue contract.
        //
        and {
          // only the owners can remove it
          signing.verify_multisig(
            extra_signatories,
            this_datum.owners.pkhs,
            this_datum.owners.threshold,
          )?,
          // single script input, no script outputs
          count.inputs_by_addr(inputs, this_addr, 1)?,
          count.outputs_by_addr(outputs, this_addr, 0)?,
        }
      }
      // updates the metadata and can change the minimum lovelace
      UpdateEntry -> {
        let Transaction { inputs, outputs, extra_signatories, datums, .. } =
          context.transaction
        // this input is being validated
        let this_input: Input = find.input_by_ref(inputs, output_reference)
        // this script address
        let this_addr: Address = this_input.output.address
        // that value going back to the contract
        let that_value: Value =
          this_input.output.value |> value.without_lovelace
        // that datum coming back to this address
        expect that_datum: QueueDatum =
          util.output_datum(outputs, this_addr, datums)
        //
        // A valid multsig can updated a queue entry. The validation logic
        // allows the minimum lovelace to change with the update so it should
        // scale naturally with metadatum changes. The update function does
        // check if the incoming datum is valid.
        //
        and {
          // that datum is valid
          queue.is_valid(that_datum)?,
          // send exactly that value to this address
          payout.at_least(this_addr, that_value, outputs)?,
          // only owners can update the data
          signing.verify_multisig(
            extra_signatories,
            this_datum.owners.pkhs,
            this_datum.owners.threshold,
          )?,
          // single script input
          count.inputs_by_addr(inputs, this_addr, 1)?,
          // single script output
          count.outputs_by_addr(outputs, this_addr, 1)?,
        }
      }
      ProcessEntry -> {
        let Transaction {
          inputs,
          reference_inputs,
          outputs,
          extra_signatories,
          mint,
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
        // the storage address, may be staked
        let storage_addr: Address =
          addresses.create_script_address(
            ref_datum.storage,
            ref_datum.staking.vkh,
          )
        // the beneficiary address, may be staked
        let beneficiary_addr: Address =
          addresses.from_wallet(this_datum.beneficiary)
        // the fraction estate payment address, may be staked
        let fraction_estate_addr: Address =
          addresses.from_wallet(ref_datum.payment)
        // what is being minted in this transaction
        let mint_list: List<(PolicyId, AssetName, Int)> =
          mint
            |> value.from_minted_value()
            |> value.flatten()
        // use the ref prefix
        let reference_tkn: AssetName =
          util.token_name(
            output_reference.transaction_id.hash,
            output_reference.output_index,
            cip68.prefix_100,
          )
        // use the rft prefix
        let rich_fungible_tkn: AssetName =
          util.token_name(
            output_reference.transaction_id.hash,
            output_reference.output_index,
            cip68.prefix_444,
          )
        // this prevents bricking the utxo with the missing datum attack
        expect _: CIP68 = util.output_datum(outputs, storage_addr, datums)
        //
        // Processing a queue entry is a multisig agreement between the
        // company and a member of the keepers of Fraction Estate. It checks
        // that the metadatum is attached to UTxO going to the cip68 storage,
        // the payment if it exists goes to the Fraction Estate reward wallet,
        // and that the beneficiary wallet gets the fractions.
        //
        and {
          // at least the reference token must go to cip 68 storage contract
          payout.at_least(
            storage_addr,
            value.from_asset(ref_datum.policy_id, reference_tkn, 1),
            outputs,
          )?,
          // it can be free or it has to be paid for
          or {
            // either its free
            list.length(this_datum.payment) == 0,
            // or at least the payment goes to the fraction estate wallet
            payout.at_least(
              fraction_estate_addr,
              values.from_tokens(this_datum.payment),
              outputs,
            )?,
          }?,
          // at least the fractions must go to the beneficiary wallet
          payout.at_least(
            beneficiary_addr,
            value.from_asset(
              ref_datum.policy_id,
              rich_fungible_tkn,
              this_datum.mint_amount,
            ),
            outputs,
          )?,
          // must mint 1 reference token
          minting.exact(mint_list, ref_datum.policy_id, reference_tkn, 1)?,
          // must mint mint_amount rich-fungible tokens
          minting.exact(
            mint_list,
            ref_datum.policy_id,
            rich_fungible_tkn,
            this_datum.mint_amount,
          )?,
          // valid owner multsig
          signing.verify_multisig(
            extra_signatories,
            this_datum.owners.pkhs,
            this_datum.owners.threshold,
          )?,
          // at least one keeper signed off
          reference.at_least_one_keeper(
            extra_signatories,
            ref_datum.keepers.pkhs,
          ),
          // single script input
          count.inputs_by_addr(inputs, this_addr, 1)?,
          // no script output
          count.outputs_by_addr(outputs, this_addr, 0)?,
          // single storage output
          count.outputs_by_addr(outputs, storage_addr, 1)?,
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