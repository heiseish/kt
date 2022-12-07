import shutil
import tempfile
import unittest
from pathlib import Path

import pytest

from kttool.actions.gen import Gen
from kttool.actions.submit import SubmissionResult, Submit


@pytest.mark.parametrize(
    "submission_result", [
        SubmissionResult(
            '10060968', 'https://open.kattis.com/submissions/10060968'
        ),
        SubmissionResult(
            '8043679', 'https://open.kattis.com/submissions/8043679'
        ),
    ]
)
def test_submit_action(submission_result):
    action = Submit()
    action.read_config_from_file()
    soup = action._query_submission_id_url(submission_result)
    result = action._parse_results_from_soup(soup)
    verdict = action._parse_verdict(result)
    assert verdict.is_done
    assert not verdict.is_rejected
    assert verdict.verdict == 'Accepted'
