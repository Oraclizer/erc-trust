#!/usr/bin/env python3
"""Unit tests of the call frame reader of the registered requests outside canonical form, on synthetic inputs."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import malformed_call_trace as trace


def token(value):
    return {"node": "KToken", "token": str(value), "sort": {"node": "KSort", "name": "Int"}}


def cell(label, *args):
    return {"node": "KApply", "label": {"node": "KLabel", "name": label, "params": []}, "args": list(args)}


def call_state(depth, account, caller):
    return cell("<callState>", cell("<id>", token(account)), cell("<caller>", token(caller)),
                cell("<callDepth>", token(depth)))


def node_document(depth, account, caller, saved=None):
    stack = cell("<callStack>", *([cell("ListItem", saved)] if saved else []))
    evm = cell("<evm>", cell("<output>", token(0)), stack, call_state(depth, account, caller))
    top = cell("<generatedTop>", cell("<foundry>", cell("<kevm>", cell("<k>", token(0)), cell("<ethereum>", evm))))
    return {"id": 1, "cterm": {"config": top, "constraints": []}}


class CurrentFrameTest(unittest.TestCase):
    def write(self, directory, document):
        path = Path(directory) / "node.json"
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def test_reads_the_current_frame_not_the_saved_one(self):
        with tempfile.TemporaryDirectory() as directory:
            saved = call_state(0, 11, 22)
            path = self.write(directory, node_document(1, 33, 11, saved))
            self.assertEqual(trace.current_frame(path), {"callDepth": 1, "account": 33, "caller": 11})

    def test_symbolic_depth_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            document = node_document(1, 33, 11)
            evm = document["cterm"]["config"]["args"][0]["args"][0]["args"][1]["args"][0]
            evm["args"][2]["args"][2]["args"][0] = {"node": "KVariable", "name": "DEPTH"}
            path = self.write(directory, document)
            with self.assertRaises(trace.TraceError):
                trace.current_frame(path)

    def test_duplicate_call_state_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            document = node_document(1, 33, 11)
            evm = document["cterm"]["config"]["args"][0]["args"][0]["args"][1]["args"][0]
            evm["args"].append(call_state(2, 44, 33))
            path = self.write(directory, document)
            with self.assertRaises(trace.TraceError):
                trace.current_frame(path)


class SegmentPathTest(unittest.TestCase):
    def graph(self, **extra):
        value = {"nodes": [1, 2, 3, 4], "edges": [{"source": 1, "target": 2, "depth": 5, "rules": []},
                                                 {"source": 2, "target": 3, "depth": 1, "rules": []},
                                                 {"source": 3, "target": 4, "depth": 7, "rules": []}]}
        value.update(extra)
        return value

    def test_linear_chain(self):
        self.assertEqual(trace.segment_path(self.graph(), 1, 4), [1, 2, 3, 4])

    def test_split_inside_the_segment_is_refused(self):
        with self.assertRaises(trace.TraceError):
            trace.segment_path(self.graph(splits=[{"source": 2, "targets": []}]), 1, 4)

    def test_cover_inside_the_segment_is_refused(self):
        with self.assertRaises(trace.TraceError):
            trace.segment_path(self.graph(covers=[{"source": 3, "target": 1}]), 1, 4)

    def test_missing_edge_is_refused(self):
        graph = self.graph()
        graph["edges"].pop()
        with self.assertRaises(trace.TraceError):
            trace.segment_path(graph, 1, 4)

    def test_second_edge_from_one_node_is_refused(self):
        graph = self.graph()
        graph["edges"].append({"source": 2, "target": 4, "depth": 1, "rules": []})
        with self.assertRaises(trace.TraceError):
            trace.segment_path(graph, 1, 4)

    def test_cycle_is_refused(self):
        graph = self.graph()
        graph["edges"][2]["target"] = 2
        with self.assertRaises(trace.TraceError):
            trace.segment_path(graph, 1, 4)


SOURCE = """theory T
begin
definition xm4_assemble where
  "xm4_assemble = \\<lparr>transaction_gas_limit = 0, transaction_external_calls = [],
     transaction_phase = TRUST_Returned\\<rparr>"
definition xm4_empty_calldata_execution :: "nat" where
  "xm4_empty_calldata_execution =
    \\<lparr>transaction_calldata = c, transaction_external_calls = [],
      transaction_phase = TRUST_Returned\\<rparr>"
lemma xm4_empty_calldata_relabels: "True" by simp
definition xm4_empty_calldata_typed_first_execution :: "nat" where
  "xm4_empty_calldata_typed_first_execution = \\<lparr>transaction_external_calls = []\\<rparr>"
end
"""


class StageRecordTest(unittest.TestCase):
    def test_record_of_the_request_supplies_the_empty_list(self):
        records = trace.stage_records(SOURCE)
        self.assertEqual(records["values"], ["[]", "[]", "[]"])
        body = trace.record_body(records, "empty-calldata", "x")
        self.assertEqual(body.count(trace.EMPTY_LIST), 1)
        self.assertNotIn("typed_first", body.splitlines()[0])

    def test_nonempty_list_is_reported(self):
        records = trace.stage_records(SOURCE.replace(
            "transaction_calldata = c, transaction_external_calls = []", "transaction_calldata = c, transaction_external_calls = calls"))
        self.assertIn("calls", records["values"])

    def test_missing_record_is_refused(self):
        with self.assertRaises(trace.TraceError):
            trace.record_body(trace.stage_records(SOURCE), "unknown-selector", "x")

    def test_ambiguous_record_is_refused(self):
        source = SOURCE.replace("lemma xm4_empty_calldata_relabels",
                                "definition ym4_empty_calldata_execution :: \"nat\" where\n  \"ym4_empty_calldata_execution = 0\"\n"
                                "lemma xm4_empty_calldata_relabels")
        with self.assertRaises(trace.TraceError):
            trace.record_body(trace.stage_records(source), "empty-calldata", "x")


if __name__ == "__main__":
    unittest.main()
