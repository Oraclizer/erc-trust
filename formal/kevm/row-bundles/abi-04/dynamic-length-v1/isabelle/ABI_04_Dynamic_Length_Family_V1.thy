theory ABI_04_Dynamic_Length_Family_V1
  imports Main
begin

definition abi04_action_tuple_words :: nat where "abi04_action_tuple_words = 21"
definition abi04_reversal_tuple_words :: nat where "abi04_reversal_tuple_words = 9"
definition abi04_second_word :: nat where "abi04_second_word = 32"
definition abi04_uint256_bound :: nat where "abi04_uint256_bound = 2 ^ 256"
definition abi04_action_envelope_bytes :: nat where "abi04_action_envelope_bytes = 740"
definition abi04_reversal_envelope_bytes :: nat where "abi04_reversal_envelope_bytes = 356"
definition abi04_action_gas_upper :: nat where "abi04_action_gas_upper = 21000 + 740 * 16"
definition abi04_reversal_gas_upper :: nat where "abi04_reversal_gas_upper = 21000 + 356 * 16"
definition abi04_tx_gas_limit :: nat where "abi04_tx_gas_limit = 1000000"

theorem abi04_dynamic_length_v1_arithmetic:
  "abi04_action_tuple_words < abi04_uint256_bound <and>
   abi04_reversal_tuple_words < abi04_uint256_bound <and>
   abi04_second_word < abi04_uint256_bound <and>
   abi04_action_envelope_bytes = 676 + 64 <and>
   abi04_reversal_envelope_bytes = 292 + 64 <and>
   abi04_action_gas_upper = 32840 <and>
   abi04_reversal_gas_upper = 26696 <and>
   abi04_action_gas_upper <le> abi04_tx_gas_limit <and>
   abi04_reversal_gas_upper <le> abi04_tx_gas_limit <and>
   3 + 3 = (6::nat) <and> 6 * 2 = (12::nat)"
  by (simp add: abi04_action_tuple_words_def abi04_reversal_tuple_words_def
      abi04_second_word_def abi04_uint256_bound_def
      abi04_action_envelope_bytes_def abi04_reversal_envelope_bytes_def
      abi04_action_gas_upper_def abi04_reversal_gas_upper_def abi04_tx_gas_limit_def)

end
