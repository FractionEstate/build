//// This staking contract handles delegation to a single pool and withdrawing
//// rewards to a single reward wallet. The pool id and reward wallet are 
//// contained in the reference data so it can be updated when required. Anyone
//// may withdraw the reward since the reward can only be withdrawn to the 
//// reward wallet. But only a valid multisig can publish a new delegation
//// certitificate.
////

use aiken/transaction.{Input, Publish, ScriptContext, Transaction, WithdrawFrom}
use aiken/transaction/certificate.{Certificate, CredentialDelegation}
use aiken/transaction/credential.{Address, Inline, ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use assist/addresses
use assist/data
use assist/find
use assist/payout
use assist/signing
use assist/types/hashes.{ValidatorHash}
use assist/types/wallet
use assist/values
use dapp/constants.{Lovelace}
use dapp/types/reference.{ReferenceDatum}
use dapp/types/staking.{Delegate, Withdraw, WithdrawRedeemer}

validator(
  // genesis token information
  genesis_pid: PolicyId,
  genesis_tkn: AssetName,
  // data reference hash
  data_ref_hash: ValidatorHash,
) {
  fn params(redeemer: WithdrawRedeemer, context: ScriptContext) -> Bool {
    let Transaction {
      reference_inputs,
      outputs,
      extra_signatories,
      withdrawals,
      ..
    } = context.transaction
    // get reference data stuff
    let ref_addr: Address = credential.from_script(data_ref_hash)
    let ref_input: Input = find.input_by_addr(reference_inputs, ref_addr)
    expect ref_datum: ReferenceDatum = data.input_datum(ref_input)
    // it can handle withdrawing or publishing a new delegation cert
    when context.purpose is {
      // handle all withdrawals here
      WithdrawFrom(stake_credential) -> {
        // all rewards are paid to the reward address
        let reward_addr: Address = addresses.from_wallet(ref_datum.payment)
        // if no reward is found then error
        let reward: Lovelace =
          find.stake_reward_by_sc(withdrawals, stake_credential)
        when redeemer is {
          // can only withdraw
          Withdraw -> and {
              // data reference must hold correct token
              values.prove_exact_nft(
                ref_input.output.value,
                genesis_pid,
                genesis_tkn,
              )?,
              // an at least here allows for small rewards to be withdrawn
              // the extra lovelace required can be provided by some other utxo
              payout.at_least(reward_addr, value.from_lovelace(reward), outputs)?,
              // the reward wallet must be valid
              wallet.is_valid(ref_datum.payment)?,
            }
          // other redeemers fail here
          _ -> False
        }
      }
      // handle all delegation certs
      Publish(certificate) ->
        when redeemer is {
          // only delegate to secific pool
          Delegate(sd) -> {
            // we need to create the certificate for the new delegation
            let new_delegation: Certificate =
              CredentialDelegation {
                delegator: Inline(ScriptCredential(sd.stake_cred)),
                delegatee: ref_datum.staking.pool_id,
              }
            and {
              // data reference must hold correct token
              values.prove_exact_nft(
                ref_input.output.value,
                genesis_pid,
                genesis_tkn,
              )?,
              // The only cert is for new delegation
              (certificate == new_delegation)?,
              // only keepers can update the data
              signing.verify_multisig(
                extra_signatories,
                ref_datum.keepers.pkhs,
                ref_datum.keepers.threshold,
              )?,
            }
          }
          // other redeemers fail here
          _ -> False
        }
      // other purposes fail here
      _ -> False
    }
  }
}