import importlib.util
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location(
    "merge_appintents", Path(__file__).parents[1] / "scripts" / "merge-appintents.py")
merge_appintents = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merge_appintents)


class MergeAppIntentsTests(unittest.TestCase):
    def test_keeps_spotify_provider_and_merges_taurus_shortcuts(self):
        spotify = {
            "actions": {"CreatePlaylistIntent": {"title": "Create"}},
            "enums": [{"identifier": "SpotifyEnum", "cases": []}],
            "autoShortcutProviderMangledName": "SpotifyProvider",
            "autoShortcuts": [{"actionIdentifier": "CreatePlaylistIntent"}],
            "shortcutTileColor": 14,
        }
        taurus = {
            "actions": {"SGLikeIntent": {"title": "Like"}},
            "enums": [{"identifier": "SGKaraokeMode", "cases": []}],
            "autoShortcutProviderMangledName": "SGAppShortcuts",
            "autoShortcuts": [{"actionIdentifier": "SGLikeIntent"}],
            "shortcutTileColor": 6,
        }

        merged = merge_appintents.merge_metadata(spotify, taurus)

        self.assertEqual(set(merged["actions"]), {"CreatePlaylistIntent", "SGLikeIntent"})
        self.assertEqual([item["identifier"] for item in merged["enums"]],
                         ["SpotifyEnum", "SGKaraokeMode"])
        self.assertEqual([item["actionIdentifier"] for item in merged["autoShortcuts"]],
                         ["CreatePlaylistIntent", "SGLikeIntent"])
        self.assertEqual(merged["autoShortcutProviderMangledName"], "SpotifyProvider")
        self.assertEqual(merged["shortcutTileColor"], 14)

    def test_uses_taurus_metadata_when_the_app_has_none(self):
        taurus = {"actions": {"SGLikeIntent": {}}, "autoShortcuts": []}
        self.assertIs(merge_appintents.merge_metadata(None, taurus), taurus)

    def test_accepts_empty_list_and_dictionary_variants_from_xcode(self):
        spotify = {
            "actions": {"SpotifyIntent": {}},
            "assistantEntities": {"SpotifyEntity": {}},
            "assistantIntents": [],
        }
        taurus = {
            "actions": {"TaurusIntent": {}},
            "assistantEntities": [],
            "assistantIntents": {"TaurusAssistantIntent": {}},
        }

        merged = merge_appintents.merge_metadata(spotify, taurus)

        self.assertEqual(merged["assistantEntities"], {"SpotifyEntity": {}})
        self.assertEqual(merged["assistantIntents"], {"TaurusAssistantIntent": {}})

    def test_preserves_spotify_shape_when_both_variants_are_empty(self):
        spotify = {"actions": {}, "assistantEntities": {}}
        taurus = {"actions": {}, "assistantEntities": []}

        merged = merge_appintents.merge_metadata(spotify, taurus)

        self.assertEqual(merged["assistantEntities"], {})

    def test_merges_list_variants_by_identifier(self):
        spotify = {"actions": {}, "assistantEntities": [{"identifier": "SpotifyEntity"}]}
        taurus = {"actions": {}, "assistantEntities": [{"identifier": "TaurusEntity"}]}

        merged = merge_appintents.merge_metadata(spotify, taurus)

        self.assertEqual([item["identifier"] for item in merged["assistantEntities"]],
                         ["SpotifyEntity", "TaurusEntity"])


if __name__ == "__main__":
    unittest.main()
