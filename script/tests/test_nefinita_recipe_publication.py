import unittest
from publish_nefinita_recipe import object_keys
from publish_resources import ManifestError


class NefinitaRecipePublicationTests(unittest.TestCase):
    def recipe(self):
        return dict(schemaVersion=1, provider="Nefinita", revision="a" * 40, version="0.3.0",
                    files={"script/build-runtime.sh": "b" * 64})

    def test_matches_app_object_layout(self):
        self.assertEqual(object_keys(self.recipe())["script/build-runtime.sh"],
                         "components/build-recipe/nefinita/dev.nefinita.build-recipe/0.3.0-aaaaaaaa/"
                         + "b" * 64 + "/script/build-runtime.sh")

    def test_rejects_invalid_paths_versions_and_hashes(self):
        for path in ("../secret", "/secret", "a//b", "a/./b", "a\\b"):
            recipe = self.recipe()
            recipe["files"] = {path: "b" * 64}
            with self.assertRaises(ManifestError):
                object_keys(recipe)
        for field, value in (("revision", "main"), ("version", "../1"), ("provider", "other")):
            recipe = self.recipe()
            recipe[field] = value
            with self.assertRaises(ManifestError):
                object_keys(recipe)


if __name__ == "__main__":
    unittest.main()
