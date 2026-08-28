theory BAL_06_Closure
  imports ERC_TRUST.TRUST_Compositional_State BAL_06_Bridge_Generated
begin

definition ordinary_transfer_post ::
  "trust_compositional_state \<Rightarrow> trust_address \<Rightarrow> trust_address \<Rightarrow> nat
   \<Rightarrow> trust_compositional_state"
where
  "ordinary_transfer_post st source destination amount =
     st\<lparr>physical_balances :=
       (physical_balances st)
         (source := physical_balances st source - amount,
          destination := physical_balances st destination + amount)\<rparr>"

definition bal06_retrieves ::
  "bal06_runtime_view \<Rightarrow> trust_compositional_state \<Rightarrow>
   trust_address \<Rightarrow> trust_address \<Rightarrow> trust_address \<Rightarrow> bool"
where
  "bal06_retrieves view st source destination other \<longleftrightarrow>
     bal06_source_balance view = physical_balances st source \<and>
     bal06_destination_balance view = physical_balances st destination \<and>
     bal06_source_frozen view = frozen_targets st source \<and>
     bal06_destination_frozen view = frozen_targets st destination \<and>
     bal06_source_backing view = custody_backing st source \<and>
     bal06_destination_backing view = custody_backing st destination \<and>
     bal06_other_balance view = physical_balances st other \<and>
     bal06_entered view = 0"

theorem abstract_ordinary_transfer_preserves_backing_and_own_frozen_floor:
  assumes distinct: "source \<noteq> destination"
      and other_source: "other \<noteq> source"
      and other_destination: "other \<noteq> destination"
      and floor: "custody_backing st source + frozen_targets st source + amount
                  \<le> physical_balances st source"
  defines "st' \<equiv> ordinary_transfer_post st source destination amount"
  shows "custody_backing st' source = custody_backing st source"
    and "frozen_targets st' source = frozen_targets st source"
    and "custody_backing st' destination = custody_backing st destination"
    and "frozen_targets st' destination = frozen_targets st destination"
    and "own_frozen_floor st' source = own_frozen_floor st source"
    and "required_floor st' source = required_floor st source"
    and "required_floor st' source \<le> physical_balances st' source"
    and "physical_balances st' other = physical_balances st other"
proof -
  have source_balance:
    "physical_balances st' source = physical_balances st source - amount"
    using distinct by (simp add: st'_def ordinary_transfer_post_def)
  have backing: "custody_backing st' source = custody_backing st source"
    by (simp add: st'_def ordinary_transfer_post_def)
  have frozen: "frozen_targets st' source = frozen_targets st source"
    by (simp add: st'_def ordinary_transfer_post_def)
  have pre_own:
    "frozen_targets st source \<le> own_physical st source"
    using floor by (auto simp: own_physical_def)
  have pre_own_floor:
    "own_frozen_floor st source = frozen_targets st source"
    using pre_own by (simp add: own_frozen_floor_def)
  have post_own:
    "frozen_targets st' source \<le> own_physical st' source"
    using floor by (auto simp: own_physical_def source_balance backing frozen)
  have own_floor:
    "own_frozen_floor st' source = own_frozen_floor st source"
    using pre_own post_own by (simp add: own_frozen_floor_def frozen)
  have required:
    "required_floor st' source = required_floor st source"
    by (simp add: required_floor_def backing own_floor)
  have source_floor_after_amount:
    "custody_backing st source + frozen_targets st source
     \<le> physical_balances st source - amount"
    using floor by arith
  show "custody_backing st' source = custody_backing st source" by (rule backing)
  show "frozen_targets st' source = frozen_targets st source" by (rule frozen)
  show "custody_backing st' destination = custody_backing st destination"
    by (simp add: st'_def ordinary_transfer_post_def)
  show "frozen_targets st' destination = frozen_targets st destination"
    by (simp add: st'_def ordinary_transfer_post_def)
  show "own_frozen_floor st' source = own_frozen_floor st source" by (rule own_floor)
  show "required_floor st' source = required_floor st source" by (rule required)
  show "required_floor st' source \<le> physical_balances st' source"
  proof -
    have "required_floor st' source = required_floor st source"
      by (rule required)
    also have "... = custody_backing st source + own_frozen_floor st source"
      by (simp only: required_floor_def)
    also have "... = custody_backing st source + frozen_targets st source"
      by (simp only: pre_own_floor)
    also have "... \<le> physical_balances st source - amount"
      by (rule source_floor_after_amount)
    also have "... = physical_balances st' source"
      by (rule source_balance[symmetric])
    finally show ?thesis .
  qed
  show "physical_balances st' other = physical_balances st other"
    using other_source other_destination
    by (simp add: st'_def ordinary_transfer_post_def)
qed

theorem ordinary_transfer_preserves_backing_and_own_frozen_floor:
  assumes distinct: "source \<noteq> destination"
      and other_source: "other \<noteq> source"
      and other_destination: "other \<noteq> destination"
      and floor: "custody_backing st source + frozen_targets st source + amount
                  \<le> physical_balances st source"
      and retrieve: "bal06_retrieves view st source destination other"
  defines "st' \<equiv> ordinary_transfer_post st source destination amount"
      and "view' \<equiv> bal06_runtime_transfer_post view amount"
  shows "bal06_retrieves view' st' source destination other"
    and "custody_backing st' source = custody_backing st source"
    and "frozen_targets st' source = frozen_targets st source"
    and "custody_backing st' destination = custody_backing st destination"
    and "frozen_targets st' destination = frozen_targets st destination"
    and "own_frozen_floor st' source = own_frozen_floor st source"
    and "required_floor st' source = required_floor st source"
    and "required_floor st' source \<le> physical_balances st' source"
    and "physical_balances st' other = physical_balances st other"
proof -
  note frame = abstract_ordinary_transfer_preserves_backing_and_own_frozen_floor
    [OF distinct other_source other_destination floor, folded st'_def]
  show "bal06_retrieves view' st' source destination other"
    using retrieve distinct other_source other_destination
    by (auto simp: bal06_retrieves_def view'_def st'_def
        bal06_runtime_transfer_post_def ordinary_transfer_post_def)
  show "custody_backing st' source = custody_backing st source" by (rule frame(1))
  show "frozen_targets st' source = frozen_targets st source" by (rule frame(2))
  show "custody_backing st' destination = custody_backing st destination" by (rule frame(3))
  show "frozen_targets st' destination = frozen_targets st destination" by (rule frame(4))
  show "own_frozen_floor st' source = own_frozen_floor st source" by (rule frame(5))
  show "required_floor st' source = required_floor st source" by (rule frame(6))
  show "required_floor st' source \<le> physical_balances st' source" by (rule frame(7))
  show "physical_balances st' other = physical_balances st other" by (rule frame(8))
qed

end
