//// The rich fungible token minter handles minting RFT from the queue and 
//// handles burning of either the RFT or the reference token. The minting
//// process is entirely handled inside the ProcessEntry endpoint of the queue
//// contract. The burning endpoint may be used by anyone with the tokens.
////

use aiken/transaction.{Input, Mint, OutputReference, ScriptContext, Transaction}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use assist/addresses
use assist/data
use assist/find
use assist/minting
use assist/types/cip68
use assist/types/hashes.{ValidatorHash}
use assist/values
use dapp/types/queue.{ProcessEntry, QueueRedeemer}
use dapp/types/reference.{ReferenceDatum}
use dapp/types/rft_minter.{BurnTokens, MintTokens, MinterRedeemer}

validator(
  // genesis token information
  genesis_pid: PolicyId,
  genesis_tkn: AssetName,
  // data reference hash
  data_ref_hash: ValidatorHash,
) {
  fn params(redeemer: MinterRedeemer, context: ScriptContext) -> Bool {
    // must be minting
    expect Mint(currency_symbol) = context.purpose
    // catch the redeemer for minting or burning
    when redeemer is {
      // this happens once per queue entry
      MintTokens -> {
        // the transaction being validated
        let Transaction { inputs, reference_inputs, redeemers, .. } =
          context.transaction
        // get reference data stuff
        let ref_addr: Address = credential.from_script(data_ref_hash)
        let ref_input: Input = find.input_by_addr(reference_inputs, ref_addr)
        expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
        let queue_addr: Address =
          addresses.create_script_address(
            ref_datum.queue,
            ref_datum.staking.vkh,
          )
        // get the queue input
        let queue_input: Input = find.input_by_addr(inputs, queue_addr)
        let queue_out_ref: OutputReference = queue_input.output_reference
        // catch that redeemer being used on the queue
        expect that_redeemer: QueueRedeemer =
          find.redeemer_by_ref(redeemers, queue_out_ref)
        // check if its the correct redeemer
        let is_corect_redeemer: Bool =
          when that_redeemer is {
            // only the process entry redeemer is allowed
            ProcessEntry -> True
            _ -> fail @"Incorrect Queue Redeemer"
          }
        //
        // The minting process is handled by the process entry inside the queue
        // contract. We simply just need to check if that redeemer is being
        // executed and that the reference data is holding the correct token.
        //
        and {
          is_corect_redeemer?,
          // must be the correct reference data
          values.prove_exact_nft(
            ref_input.output.value,
            genesis_pid,
            genesis_tkn,
          )?,
        }
      }
      // this can happen whenever, set burn_amt to zero when burning the ref token
      BurnTokens { burn_amt } -> {
        // the transaction being validated
        let Transaction { mint, .. } = context.transaction
        // what is being minted in this transaction
        let mint_list: List<(PolicyId, AssetName, Int)> =
          mint
            |> value.from_minted_value()
            |> value.flatten()
        //
        // Anyone holding the fractional tokens may burn their tokens if they
        // wish. The burning is an OR statement here so either the reference
        // or the rft or both can be burned. The reference burning burned here
        // implies it is being removed from the storage contract or is already
        // removed from that contract.
        //
        and {
          // burn amount must be negative or zero
          (burn_amt <= 0)?,
          // one ref token or any amount of tokens or both
          or {
            // burn only 1 ref token
            minting.by_prefix(mint_list, currency_symbol, cip68.prefix_100, -1)?,
            // burn any amount of the fractions
            minting.by_prefix(
              mint_list,
              currency_symbol,
              cip68.prefix_444,
              burn_amt,
            )?,
          }?,
        }
      }
    }
  }
}