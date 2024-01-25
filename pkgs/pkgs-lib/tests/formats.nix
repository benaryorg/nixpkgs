{ pkgs }:
let
  inherit (pkgs) lib formats;

  # merging allows us to add metadata to the input
  # this makes error messages more readable during development
  mergeInput = name: format: input:
    format.type.merge [] [
      {
        # explicitly throw here to trigger the code path that prints the error message for users
        value = lib.throwIfNot (format.type.check input) (builtins.trace input "definition does not pass the type's check function") input;
        # inject the name
        file = "format-test-${name}";
      }
    ];

  # run a diff between expected and real output
  runDiff = name: drv: expected: pkgs.runCommand name {
    passAsFile = ["expected"];
    inherit expected drv;
  } ''
    if diff -u "$expectedPath" "$drv"; then
      touch "$out"
    else
      echo
      echo "Got different values than expected; diff above."
      exit 1
    fi
  '';

  # use this to check for proper serialization
  shouldPass = format: input: expected: name: {
    name = "pass-${name}";
    path = runDiff "test-format-${name}" (format.generate "test-format-${name}" (mergeInput name format input)) expected;
  };

  # use this function to assert that a type check must fail
  # note that as per 352e7d330a26 and 352e7d330a26 the type checking of attrsets and lists are not strict
  # this means that primarily the type check will catch custom module types
  shouldFail = format: input: name: {
    name = "pass-${name}";
    path = if !(format.type.check input) then
        # the check failing is what we want, so don't do anything here
        pkgs.runCommand "test-format-${name}" {} "touch $out"
      else
        # bail with some verbose information in case the type check passes
        pkgs.runCommand "test-format-${name}" {
            passAsFile = [ "inputText" ];
            testName = name;
            # toXML seems to be the only way to stringify input that is generic over *any* data type
            inputText = builtins.toXML input;
          }
          ''
            echo "Type check $testName passed when it shouldn't."
            echo "The following data was used as input:"
            echo
            cat "$inputTextPath"
            exit 1
          '';
  };

  runBuildTests = (lib.flip lib.pipe) [
    lib.attrsToList
    (builtins.map ({ name, value }: value name))
    (pkgs.linkFarm "nixpkgs-pkgs-lib-format-tests")
  ];

in runBuildTests {

  jsonAtoms = shouldPass
    (formats.json {})
    {
      null = null;
      false = false;
      true = true;
      int = 10;
      float = 3.141;
      str = "foo";
      attrs.foo = null;
      list = [ null null ];
      path = ./formats.nix;
    }
    ''
      {
        "attrs": {
          "foo": null
        },
        "false": false,
        "float": 3.141,
        "int": 10,
        "list": [
          null,
          null
        ],
        "null": null,
        "path": "${./formats.nix}",
        "str": "foo",
        "true": true
      }
    '';

  yamlAtoms = shouldPass
    (formats.yaml {})
    {
      null = null;
      false = false;
      true = true;
      float = 3.141;
      str = "foo";
      attrs.foo = null;
      list = [ null null ];
      path = ./formats.nix;
    }
    ''
      attrs:
        foo: null
      'false': false
      float: 3.141
      list:
      - null
      - null
      'null': null
      path: ${./formats.nix}
      str: foo
      'true': true
    '';

  iniAtoms = shouldPass
    (formats.ini {})
    {
      foo = {
        bool = true;
        int = 10;
        float = 3.141;
        str = "string";
      };
    }
    ''
      [foo]
      bool=true
      float=3.141000
      int=10
      str=string
    '';

  iniNoAttrsets = shouldFail
    (formats.ini {})
    {
      foo = {
        bar = { baz = "quux"; };
      };
    };

  iniDuplicateKeys = shouldPass
    (formats.ini { listsAsDuplicateKeys = true; })
    {
      foo = {
        bar = [ null true "test" 1.2 10 ];
        baz = false;
        qux = "qux";
      };
    }
    ''
      [foo]
      bar=null
      bar=true
      bar=test
      bar=1.200000
      bar=10
      baz=false
      qux=qux
    '';

  iniListToValue = shouldPass
    (formats.ini { listToValue = lib.concatMapStringsSep ", " (lib.generators.mkValueStringDefault {}); })
    {
      foo = {
        bar = [ null true "test" 1.2 10 ];
        baz = false;
        qux = "qux";
      };
    }
    ''
      [foo]
      bar=null, true, test, 1.200000, 10
      baz=false
      qux=qux
    '';

  keyValueAtoms = shouldPass
    (formats.keyValue {})
    {
      bool = true;
      int = 10;
      float = 3.141;
      str = "string";
    }
    ''
      bool=true
      float=3.141000
      int=10
      str=string
    '';

  keyValueDuplicateKeys = shouldPass
    (formats.keyValue { listsAsDuplicateKeys = true; })
    {
      bar = [ null true "test" 1.2 10 ];
      baz = false;
      qux = "qux";
    }
    ''
      bar=null
      bar=true
      bar=test
      bar=1.200000
      bar=10
      baz=false
      qux=qux
    '';

  keyValueListToValue = shouldPass
    (formats.keyValue { listToValue = lib.concatMapStringsSep ", " (lib.generators.mkValueStringDefault {}); })
    {
      bar = [ null true "test" 1.2 10 ];
      baz = false;
      qux = "qux";
    }
    ''
      bar=null, true, test, 1.200000, 10
      baz=false
      qux=qux
    '';

  tomlAtoms = shouldPass
    (formats.toml {})
    {
      false = false;
      true = true;
      int = 10;
      float = 3.141;
      str = "foo";
      attrs.foo = "foo";
      list = [ 1 2 ];
      level1.level2.level3.level4 = "deep";
    }
    ''
      false = false
      float = 3.141
      int = 10
      list = [1, 2]
      str = "foo"
      true = true
      [attrs]
      foo = "foo"

      [level1.level2.level3]
      level4 = "deep"
    '';

  # This test is responsible for
  #   1. testing type coercions
  #   2. providing a more readable example test
  # Whereas java-properties/default.nix tests the low level escaping, etc.
  javaProperties = shouldPass
    (formats.javaProperties {})
    {
      floaty = 3.1415;
      tautologies = true;
      contradictions = false;
      foo = "bar";
      # # Disallowed at eval time, because it's ambiguous:
      # # add to store or convert to string?
      # root = /root;
      "1" = 2;
      package = pkgs.hello;
      "ütf 8" = "dûh";
      # NB: Some editors (vscode) show this _whole_ line in right-to-left order
      "الجبر" = "أكثر من مجرد أرقام";
    }
    ''
      # Generated with Nix

      1 = 2
      contradictions = false
      floaty = 3.141500
      foo = bar
      package = ${pkgs.hello}
      tautologies = true
      \u00fctf\ 8 = d\u00fbh
      \u0627\u0644\u062c\u0628\u0631 = \u0623\u0643\u062b\u0631 \u0645\u0646 \u0645\u062c\u0631\u062f \u0623\u0631\u0642\u0627\u0645
    '';
}
