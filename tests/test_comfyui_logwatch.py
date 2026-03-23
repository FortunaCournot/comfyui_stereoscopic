import unittest

from api.python.comfyui_logwatch import matches_crash


class ComfyUILogwatchTest(unittest.TestCase):
    def test_matches_crash_for_out_of_memory_lines(self) -> None:
        samples = [
            "torch.OutOfMemoryError: Allocation on device 0 would exceed allowed memory. (out of memory)\n",
            "torch.cuda.OutOfMemoryError: CUDA out of memory. Tried to allocate 512.00 MiB\n",
            "RuntimeError: CUDA out of memory while allocating tensor\n",
            "Allocation on device 0 would exceed allowed memory. (out of memory)\n",
        ]

        for sample in samples:
            self.assertTrue(matches_crash(sample), msg=sample)

    def test_does_not_match_memory_summary_lines(self) -> None:
        samples = [
            "Memory summary: |===========================================================================|\n",
            "Currently allocated     : 13.24 GiB\n",
            "Requested               : 721.15 MiB\n",
            "Got an OOM, unloading all loaded models.\n",
        ]

        for sample in samples:
            self.assertFalse(matches_crash(sample), msg=sample)


if __name__ == "__main__":
    unittest.main()