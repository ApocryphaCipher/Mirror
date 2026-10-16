defmodule MirrorWeb.WizardLiveTest do
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mirror.SessionStore

  setup %{conn: conn} do
    sid = "wizard-test-#{System.unique_integer([:positive])}"
    %{conn: init_test_session(conn, %{"mirror_session_id" => sid}), sid: sid}
  end

  defp load_save(sid) do
    state = Mirror.SaveManager.normalize_state(%{save: %{raw: Mirror.WizardFixture.synthetic()}})
    SessionStore.put(sid, state)
  end

  test "no save loaded says so", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/wizard/1")
    assert html =~ "No save is loaded"
  end

  test "shows the wizard on a gradient of the banner colour", %{conn: conn, sid: sid} do
    load_save(sid)
    {:ok, view, html} = live(conn, ~p"/wizard/1")

    assert has_element?(view, "#wizard-name", "Jafar")
    assert html =~ "1234"
    assert html =~ "12 Sorcery"
    assert html =~ "Alchemy, Famous"
    assert html =~ "linear-gradient(to bottom, #{MirrorWeb.WizardPanel.colour(:blue)}"
    assert has_element?(view, "#wizard-circle[href='/myrror?x=38&y=21']")
    assert has_element?(view, "#header-wizards a[href='/wizard/2']", "Sharee")
  end

  test "lists a wizard's heroes, or says there are none", %{conn: conn, sid: sid} do
    load_save(sid)
    {:ok, view, _} = live(conn, ~p"/wizard/1")
    assert has_element?(view, "#wizard-heroes", "none")

    entry =
      <<1::little-signed-16>> <>
        String.pad_trailing("Harold", 14, <<0>>) <>
        :binary.copy(<<255>>, 6) <> :binary.copy(<<0>>, 6)

    unit =
      <<7, 17, 0, 0, 2, 31, 0, 0, 0, 0, 0, 0, 2, 0, 27::little-16>> <> :binary.copy(<<0>>, 16)

    raw =
      Mirror.WizardFixture.synthetic()
      |> Mirror.WizardFixture.field(
        0,
        0x76,
        entry <> :binary.copy(<<-1::little-signed-16>> <> :binary.copy(<<0>>, 26), 5)
      )
      |> Mirror.WizardFixture.put_bytes(0x9E2, <<2::little-16>>)
      |> Mirror.WizardFixture.put_bytes(0x00B734 + 32, unit)

    SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
    {:ok, view, _} = live(conn, ~p"/wizard/1")
    assert has_element?(view, "#wizard-hero-0", "Harold")
    assert has_element?(view, "#wizard-hero-0", "level 2")
    assert has_element?(view, "#wizard-hero-0", "27 xp")
  end

  test "a hero's name and experience are edited from the wizard page, as one undo step",
       %{conn: conn, sid: sid} do
    raw = Mirror.WizardFixture.with_hero(Mirror.WizardFixture.synthetic())
    SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
    {:ok, view, _} = live(conn, ~p"/wizard/1")

    refute has_element?(view, "#wizard-hero-form-0")
    view |> element("#wizard-edit-toggle") |> render_click()
    assert has_element?(view, "#wizard-hero-form-0")

    before = SessionStore.get(sid)

    view
    |> element("#wizard-hero-form-0")
    |> render_submit(%{"hero" => %{"name" => "Sir Harold", "experience" => "150"}})

    assert has_element?(
             view,
             "#wizard-note",
             "Edited hero Harold: name Sir Harold, experience 150"
           )

    assert has_element?(view, "#wizard-hero-0", "Sir Harold")
    assert has_element?(view, "#wizard-hero-0", "150 xp")

    after_state = SessionStore.get(sid)
    assert length(after_state.history.arcanus) == length(before.history.arcanus) + 1
    {undone, _} = Mirror.Editor.undo(after_state, :arcanus)
    assert undone.save.raw == before.save.raw

    # a bad value is refused in words and changes nothing
    view
    |> element("#wizard-hero-form-0")
    |> render_submit(%{"hero" => %{"level" => "99"}})

    assert has_element?(view, "#wizard-note", "Level is a whole number")
    assert SessionStore.get(sid).save.raw == after_state.save.raw
  end

  test "shows a hero's items and the vault in words", %{conn: conn, sid: sid} do
    raw =
      Mirror.WizardFixture.synthetic()
      |> Mirror.WizardFixture.with_hero([1, 2, -1])
      |> Mirror.WizardFixture.with_items(
        %{
          1 => {"Mae Govannon", 0, 1, 1200, [1, 0, 1, 0, 0, 5, 0, 0], 0, 0},
          2 => {"Staff of Zap", 4, 4, 900, [0, 0, 0, 0, 0, 0, 0, 67], 4, 0},
          9 => {"Spare Shield", 7, 5, 300, [0, 0, 3, 0, 0, 0, 0, 0], 0, 0x4000}
        },
        0,
        [9]
      )

    SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
    {:ok, view, _} = live(conn, ~p"/wizard/1")

    assert has_element?(view, "#wizard-hero-0-item-1", "Mae Govannon")
    assert has_element?(view, "#wizard-hero-0-item-1", "Sword")
    assert has_element?(view, "#wizard-hero-0-item-1", "1200 gold")
    assert has_element?(view, "#wizard-hero-0-item-1", "+5 Spell Skill")
    assert has_element?(view, "#wizard-hero-0-item-2", "Staff of Zap")
    assert has_element?(view, "#wizard-vault-item-9", "Spare Shield")
    assert has_element?(view, "#wizard-vault-item-9", "+3 Defense")
    refute has_element?(view, "#wizard-vault", "no spare items")
  end

  test "an item is edited in place from the wizard page, as one undo step", %{
    conn: conn,
    sid: sid
  } do
    raw =
      Mirror.WizardFixture.synthetic()
      |> Mirror.WizardFixture.with_hero([1, -1, -1])
      |> Mirror.WizardFixture.with_items(
        %{
          1 => {"Mae Govannon", 0, 1, 1200, [1, 0, 1, 0, 0, 5, 0, 0], 0, 0},
          9 => {"Spare Shield", 7, 5, 300, [0, 0, 3, 2, 0, 0, 0, 0], 0, 0}
        },
        0,
        [9]
      )

    SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
    {:ok, view, _} = live(conn, ~p"/wizard/1")

    refute has_element?(view, "#wizard-item-form-1")
    view |> element("#wizard-edit-toggle") |> render_click()
    assert has_element?(view, "#wizard-item-form-1")
    assert has_element?(view, "#wizard-item-form-9")
    # movement is shown as the screen does: the byte 2 is +1
    assert has_element?(view, "#wizard-item-form-9 input[name='item[movement]'][value='1']")

    before = SessionStore.get(sid)

    view
    |> element("#wizard-item-form-9")
    |> render_submit(%{"item" => %{"name" => "Big Shield", "cost" => "500", "movement" => "2.5"}})

    assert has_element?(
             view,
             "#wizard-note",
             "Edited item Spare Shield: name Big Shield, cost 500, movement 2.5"
           )

    assert has_element?(view, "#wizard-vault-item-9", "Big Shield")
    assert has_element?(view, "#wizard-vault-item-9", "500 gold")

    edited = SessionStore.get(sid)
    assert length(edited.history.arcanus) == length(before.history.arcanus) + 1
    {:ok, items} = Mirror.SaveFile.Items.parse(edited.save.raw)

    assert %{name: "Big Shield", cost: 500, movement: 5, defense: 3} =
             Enum.find(items, &(&1.index == 9))

    {undone, _} = Mirror.Editor.undo(edited, :arcanus)
    assert undone.save.raw == before.save.raw

    # a bad value is refused in words and changes nothing
    view |> element("#wizard-item-form-1") |> render_submit(%{"item" => %{"attack" => "99"}})
    assert has_element?(view, "#wizard-note", "Stats stay within")
    assert SessionStore.get(sid).save.raw == edited.save.raw
  end

  test "an item the wizard does not hold cannot be edited from his page", %{conn: conn, sid: sid} do
    raw =
      Mirror.WizardFixture.synthetic()
      |> Mirror.WizardFixture.with_hero([1, -1, -1])
      |> Mirror.WizardFixture.with_items(%{
        1 => {"Mae Govannon", 0, 1, 1200, [1, 0, 1, 0, 0, 5, 0, 0], 0, 0},
        7 => {"Elsewhere", 6, 6, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0}
      })

    SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
    {:ok, view, _} = live(conn, ~p"/wizard/1")
    view |> element("#wizard-edit-toggle") |> render_click()

    render_hook(view, "item_edit", %{"index" => "7", "item" => %{"name" => "Hijacked"}})
    assert has_element?(view, "#wizard-note", "no longer in the save")
    assert SessionStore.get(sid).save.raw == raw
  end

  test "an empty vault and a hero with no items say so or show nothing", %{conn: conn, sid: sid} do
    SessionStore.put(
      sid,
      Mirror.SaveManager.normalize_state(%{
        save: %{raw: Mirror.WizardFixture.with_hero(Mirror.WizardFixture.synthetic())}
      })
    )

    {:ok, view, _} = live(conn, ~p"/wizard/1")
    assert has_element?(view, "#wizard-vault", "no spare items")
    refute has_element?(view, "#wizard-hero-0 li")
  end

  test "shows the relations table and the active global enchantments", %{conn: conn, sid: sid} do
    load_save(sid)
    {:ok, view, _} = live(conn, ~p"/wizard/1")

    assert has_element?(view, "#wizard-relation-1", "Sharee")
    assert has_element?(view, "#wizard-relation-1", "Wizard pact")
    assert has_element?(view, "#wizard-relation-1", "+25")
    assert has_element?(view, "#wizard-relation-1 a[href='/wizard/2']")
    assert has_element?(view, "#wizard-relation-5", "Neutral")
    assert has_element?(view, "#wizard-relation-5", "-81")
    refute has_element?(view, "#wizard-relation-5", "not met")
    # war and the pact are both confirmed in the game: no "?"
    assert has_element?(view, "#wizard-relation-5", "War")
    refute has_element?(view, "#wizard-relation-5", "War?")
    refute has_element?(view, "#wizard-relation-1", "Wizard pact?")

    assert has_element?(view, "#wizard-globals", "Aura of Majesty")
    assert has_element?(view, "#wizard-globals", "Just Cause")

    {:ok, rival, _} = live(conn, ~p"/wizard/2")
    assert has_element?(rival, "#wizard-globals", "none cast by this wizard")
    assert has_element?(rival, "#wizard-relation-0 a[href='/wizard/1']")
  end

  test "a missing wizard answers 404 with the note; an existing one 200", %{conn: conn, sid: sid} do
    assert get(conn, ~p"/wizard/6").status == 404
    assert get(conn, ~p"/wizard/abc").status == 404
    # in range, nothing loaded yet: 200 with "no save is loaded"
    assert html_response(get(conn, ~p"/wizard/1"), 200) =~ "No save is loaded"

    load_save(sid)
    assert get(conn, ~p"/wizard/1").status == 200
    resp = get(conn, ~p"/wizard/3")
    assert html_response(resp, 404) =~ "There is no wizard 3"
  end

  test "the page says so when the wizard disappears from the save", %{conn: conn, sid: sid} do
    load_save(sid)
    {:ok, view, _} = live(conn, ~p"/wizard/2")
    refute has_element?(view, "#wizard-missing")

    # the loaded save changes underneath the open page (another tab, an undo, a new load)
    raw = Mirror.WizardFixture.synthetic()
    <<head::binary-size(0x9E8 + 0x4C8 + 1), _::binary-size(20), tail::binary>> = raw
    SessionStore.put(sid, %{save: %{raw: head <> :binary.copy(<<0>>, 20) <> tail}})

    assert has_element?(view, "#wizard-missing", "There is no wizard 2")
  end

  describe "editing" do
    defp submit(view, fields),
      do: view |> element("#wizard-form") |> render_submit(%{"wizard" => fields})

    test "the form appears in edit mode, an apply is one undo step and shows on the page",
         %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      refute has_element?(view, "#wizard-form")

      view |> element("#wizard-edit-toggle") |> render_click()
      assert has_element?(view, "#wizard-form")

      before = SessionStore.get(sid)
      submit(view, %{"gold" => "5000", "name" => "Jafar the Great", "retorts_present" => "1"})

      assert has_element?(view, "#wizard-note", "Edited Jafar: gold 5000")
      assert has_element?(view, "#wizard-name", "Jafar the Great")
      assert render(view) =~ "5000"

      after_state = SessionStore.get(sid)
      assert Mirror.Editor.changed_record_count(after_state) == 1
      assert length(after_state.history.arcanus) == length(before.history.arcanus) + 1

      # Undo restores the old bytes
      {undone, _} = Mirror.Editor.undo(after_state, :arcanus)
      assert undone.save.raw == before.save.raw
    end

    test "a global enchantment is ticked in the form; Time Stop's box is disabled",
         %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()

      assert has_element?(view, "input[name='wizard[globals][3]'][checked]")
      assert has_element?(view, "input[name='wizard[globals][6]'][disabled]")

      # Nature Awareness (7) ticked; the form's own ticked boxes (3, 18) are merged in by the test helper
      # (unticking is covered by the WizardPanel tests)
      submit(view, %{"globals_present" => "1", "globals" => %{"7" => "on"}})

      assert has_element?(view, "#wizard-note", "global enchantments")
      assert render(view) =~ "Nature Awareness"
      assert has_element?(view, "#wizard-globals li", "Aura of Majesty")
      assert has_element?(view, "#wizard-globals li", "Just Cause")

      raw = SessionStore.get(sid).save.raw

      assert binary_part(raw, 0x9E8 + 0x482, 24) ==
               for(i <- 0..23, into: <<>>, do: <<if(i in [3, 7, 18], do: 1, else: 0)>>)
    end

    test "a bad value is refused with the reason and changes nothing", %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      raw = SessionStore.get(sid).save.raw

      submit(view, %{"gold" => "99999"})
      assert has_element?(view, "#wizard-note", "0 to 30000")

      submit(view, %{"name" => "Zoë"})
      assert has_element?(view, "#wizard-note", "no accents")

      submit(view, %{"gold" => "1234"})
      assert has_element?(view, "#wizard-note", "Nothing to change")

      assert SessionStore.get(sid).save.raw == raw
    end

    test "an apply compares with the save as it is now, not as the page was drawn",
         %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()

      # another tab changes the gold and the name after this page was drawn
      {:ok, _} =
        SessionStore.update(sid, fn current ->
          {:ok, raw, _} =
            Mirror.SaveFile.Structures.edit_wizard(current.save.raw, 0, gold: 111, name: "Merlin")

          put_in(current.save.raw, raw)
        end)

      # this form was drawn with gold 1234 and the old name, and only mana is changed on it
      submit(view, %{"gold" => "111", "name" => "Merlin", "mana" => "9"})

      assert has_element?(view, "#wizard-note", "Edited Merlin: mana 9")
      refute has_element?(view, "#wizard-note", "gold")
    end

    test "malformed form values show a note instead of crashing the page", %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()

      render_hook(view, "wizard_edit", %{"wizard" => %{"name" => nil}})
      assert has_element?(view, "#wizard-note", "1 to 19")
      render_hook(view, "wizard_edit", %{"wizard" => %{"books" => "x"}})
      assert has_element?(view, "#wizard-note", "Books")

      render_hook(view, "wizard_edit", %{
        "wizard" => %{"retorts_present" => "1", "retorts" => nil}
      })

      assert has_element?(view, "#wizard-note", "retorts")
    end

    defp library(sid), do: binary_part(SessionStore.get(sid).save.raw, 0x9E8 + 0x264, 214)

    test "Learn every spell of a realm is one undo step and shows the count", %{
      conn: conn,
      sid: sid
    } do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      before = SessionStore.get(sid)

      view |> element("#learn-death") |> render_click()

      lib = library(sid)
      # death is spells 161..200: every one known now, nothing else changed
      assert binary_part(lib, 160, 40) == :binary.copy(<<2>>, 40)

      assert binary_part(lib, 0, 160) ==
               binary_part(Mirror.WizardFixture.synthetic(), 0x9E8 + 0x264, 160)

      assert has_element?(view, "#wizard-spells-death", "40 of 40 known")
      assert has_element?(view, "#wizard-note", "Edited Jafar: 40 spells")
      assert length(SessionStore.get(sid).history.arcanus) == length(before.history.arcanus) + 1

      # nothing left to learn
      view |> element("#learn-death") |> render_click()
      assert has_element?(view, "#wizard-note", "Nothing to change")
    end

    test "the form changes spells, what is researched and the points left", %{
      conn: conn,
      sid: sid
    } do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()

      # spells 1 and 41 were known; keep 41, learn 3, drop 1 (the test form starts with 1 ticked, as the page draws it)
      submit(view, %{
        "spells_present" => "1",
        "spells" => %{"1" => false, "3" => "on", "41" => "on"},
        "researching" => "3",
        "research_left" => "1"
      })

      raw = SessionStore.get(sid).save.raw
      assert binary_part(raw, 0x9E8 + 0x264, 3) == <<1, 1, 2>>
      assert binary_part(raw, 0x9E8 + 0x262, 2) == <<3::little-16>>
      assert binary_part(raw, 0x9E8 + 0x25A, 2) == <<1::little-16>>
      assert has_element?(view, "#wizard-researching", "1 research points left")
    end

    test "view mode lists the known spells and has no spell controls", %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, html} = live(conn, ~p"/wizard/1")
      assert has_element?(view, "#wizard-spells-nature", "1 of 40 known")
      refute html =~ "learn-death"
      refute has_element?(view, "#wizard-research-edit")
    end

    test "a spell the game does not offer is refused, with the reason", %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      raw = SessionStore.get(sid).save.raw

      submit(view, %{"researching" => "98"})
      assert has_element?(view, "#wizard-note", "research list")
      assert SessionStore.get(sid).save.raw == raw
    end

    defp rel_bytes(sid, owner, other) do
      raw = SessionStore.get(sid).save.raw
      block = 0x9E8 + owner * 0x4C8 + 0x128
      <<r::signed>> = binary_part(raw, block + 42 + other, 1)
      {r, :binary.at(raw, block + 48 + other)}
    end

    test "the relation rows are edited in edit mode and written on both wizards", %{
      conn: conn,
      sid: sid
    } do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      refute has_element?(view, "select[name='wizard[relations][1][status]']")
      view |> element("#wizard-edit-toggle") |> render_click()
      assert has_element?(view, "select[name='wizard[relations][1][status]']")
      refute has_element?(view, "select[name='wizard[relations][5][status]']")

      submit(view, %{
        "relations_present" => "1",
        "relations" => %{"1" => %{"relation" => "-60", "status" => "3"}}
      })

      assert {-60, 3} == rel_bytes(sid, 0, 1)
      assert {-60, 3} == rel_bytes(sid, 1, 0)
      assert has_element?(view, "#wizard-note", "Edited Jafar: relations with Sharee")
      # still in edit mode, so the row shows the inputs with the new values
      assert has_element?(
               view,
               "input[name='wizard[relations][1][relation]'][value='-60']"
             )

      assert has_element?(
               view,
               "select[name='wizard[relations][1][status]'] option[value='3'][selected]"
             )
    end

    test "an out-of-range relation is refused and nothing is written", %{conn: conn, sid: sid} do
      load_save(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      raw = SessionStore.get(sid).save.raw

      submit(view, %{
        "relations_present" => "1",
        "relations" => %{"1" => %{"relation" => "500", "status" => "1"}}
      })

      assert has_element?(view, "#wizard-note", "-100 to 100")
      assert SessionStore.get(sid).save.raw == raw
    end

    test "a banished wizard is tagged on his own page and in the others' tables, with no edit controls",
         %{conn: conn, sid: sid} do
      state =
        Mirror.SaveManager.normalize_state(%{
          save: %{raw: Mirror.WizardFixture.synthetic() |> Mirror.WizardFixture.banish(1)}
        })

      SessionStore.put(sid, state)

      {:ok, rival, _} = live(conn, ~p"/wizard/2")
      assert has_element?(rival, "#wizard-banished", "Banished")

      {:ok, view, _} = live(conn, ~p"/wizard/1")
      refute has_element?(view, "#wizard-banished")
      assert has_element?(view, "#wizard-relation-1", "banished")
      view |> element("#wizard-edit-toggle") |> render_click()
      refute has_element?(view, "select[name='wizard[relations][1][status]']")
    end
  end

  describe "moving items" do
    defp load_moving(sid) do
      raw =
        Mirror.WizardFixture.synthetic()
        |> Mirror.WizardFixture.with_hero([1, 2, -1])
        |> Mirror.WizardFixture.with_items(
          %{
            1 => {"Sword", 0, 1, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
            2 => {"Shield", 7, 5, 100, [0, 0, 1, 0, 0, 0, 0, 0], 0, 0},
            3 => {"Amulet", 6, 6, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
            9 => {"Spare Shield", 7, 5, 100, [0, 0, 2, 0, 0, 0, 0, 0], 0, 0}
          },
          0,
          [9, 3]
        )

      SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
      raw
    end

    test "an item moves from the vault to the hero and back, each as one undo step", %{
      conn: conn,
      sid: sid
    } do
      load_moving(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      refute has_element?(view, "#wizard-item-move-3")
      view |> element("#wizard-edit-toggle") |> render_click()

      assert has_element?(view, "#wizard-item-move-3 option[value='hero:0:2']", "Harold")
      # the spare shield has nowhere to go, so it has no move form
      refute has_element?(view, "#wizard-item-move-9")

      before = SessionStore.get(sid)
      view |> element("#wizard-item-move-3") |> render_submit(%{"to" => "hero:0:2"})

      assert has_element?(view, "#wizard-note", "Moved Amulet to Harold")
      assert has_element?(view, "#wizard-hero-0-item-3", "Amulet")
      refute has_element?(view, "#wizard-vault-item-3")

      moved = SessionStore.get(sid)
      assert length(moved.history.arcanus) == length(before.history.arcanus) + 1
      assert Mirror.SaveFile.Items.vault_places(moved.save.raw, 0) == [9, nil, nil, nil]

      # back to the vault
      view |> element("#wizard-item-move-3") |> render_submit(%{"to" => "vault:1"})
      assert has_element?(view, "#wizard-vault-item-3", "Amulet")

      assert Mirror.SaveFile.Items.vault_places(SessionStore.get(sid).save.raw, 0) == [
               9,
               3,
               nil,
               nil
             ]

      {undone, _} = Mirror.Editor.undo(moved, :arcanus)
      assert undone.save.raw == before.save.raw
    end

    test "a place that is no longer free, or an item not held, is refused in words", %{
      conn: conn,
      sid: sid
    } do
      raw = load_moving(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()

      # the sword's own place: the hero's first place is taken, as a stale form would find it
      render_hook(view, "item_move", %{"index" => "3", "to" => "hero:0:0"})
      assert has_element?(view, "#wizard-note", "already taken")

      render_hook(view, "item_move", %{"index" => "3", "to" => "hero:0:1"})
      assert has_element?(view, "#wizard-note", "already taken")

      render_hook(view, "item_move", %{"index" => "77", "to" => "vault:3"})
      assert has_element?(view, "#wizard-note", "no longer in the save")

      render_hook(view, "item_move", %{"index" => "9", "to" => "hero:0:2"})
      assert has_element?(view, "#wizard-note", "place of its own kind")

      assert SessionStore.get(sid).save.raw == raw
    end
  end

  describe "filling and emptying item places" do
    setup do
      premade = [
        %{
          number: 7,
          name: "Ring of Power",
          slot: 6,
          type: 6,
          cost: 600,
          icon: 4,
          stats: <<0, 0, 2, 2, 2, 5, 0, 0>>,
          charges: 0,
          abilities: 0,
          slot_name: "misc",
          type_name: "Misc"
        },
        %{
          number: 1,
          name: "Black Asp",
          slot: 1,
          type: 0,
          cost: 250,
          icon: 3,
          stats: <<1, 0, 0, 0, 0, 0, 0, 0>>,
          charges: 0,
          abilities: 0x200,
          slot_name: "melee weapon",
          type_name: "Sword"
        }
      ]

      :persistent_term.put({Mirror.ItemData, :table}, premade)
      on_exit(fn -> :persistent_term.erase({Mirror.ItemData, :table}) end)
      :ok
    end

    defp load_places(sid) do
      raw =
        Mirror.WizardFixture.synthetic()
        |> Mirror.WizardFixture.with_hero([1, 2, -1])
        |> Mirror.WizardFixture.with_items(
          %{
            1 => {"Sword", 0, 1, 100, [0, 0, 0, 0, 0, 0, 0, 0], 0, 0},
            2 => {"Shield", 7, 5, 100, [0, 0, 1, 0, 0, 0, 0, 0], 0, 0},
            9 => {"Spare Shield", 7, 5, 100, [0, 0, 2, 0, 0, 0, 0, 0], 0, 0}
          },
          0,
          [9]
        )

      SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
    end

    test "the forms show only in edit mode, each place with the choices of its kind", %{
      conn: conn,
      sid: sid
    } do
      load_places(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      refute has_element?(view, "#wizard-place-hero-0-2")
      view |> element("#wizard-edit-toggle") |> render_click()

      assert has_element?(view, "#wizard-place-hero-0-2 option[value='item:7']", "Ring of Power")
      refute has_element?(view, "#wizard-place-hero-0-2 option[value='item:1']")
      assert has_element?(view, "#wizard-place-hero-0-0 option[value='item:1']", "Black Asp")
      assert has_element?(view, "#wizard-place-vault-3 option[value='item:7']")
      assert has_element?(view, "#wizard-place-vault-3 option[value='item:1']")
    end

    test "an empty place is filled, as one undo step, and emptied again", %{conn: conn, sid: sid} do
      load_places(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      before = SessionStore.get(sid)

      view |> element("#wizard-place-hero-0-2") |> render_submit(%{"choice" => "item:7"})
      assert has_element?(view, "#wizard-note", "Put Ring of Power in Harold")
      assert has_element?(view, "#wizard-hero-0 li", "Ring of Power")

      filled = SessionStore.get(sid)
      assert length(filled.history.arcanus) == length(before.history.arcanus) + 1
      {:ok, items} = Mirror.SaveFile.Items.parse(filled.save.raw)
      # Ring of Power movement 2 as shown is stored as 4 half points
      assert %{name: "Ring of Power", movement: 4, cost: 600, resistance: 2} =
               Enum.find(items, &(&1.name == "Ring of Power"))

      # the game's "in play" flag for premade number 7 is set, as the game does when it makes an item
      assert :binary.at(filled.save.raw, byte_size(filled.save.raw) - 810 + 6) == 1

      {undone, _} = Mirror.Editor.undo(filled, :arcanus)
      assert undone.save.raw == before.save.raw

      view |> element("#wizard-place-hero-0-2") |> render_submit(%{"choice" => "clear"})
      assert has_element?(view, "#wizard-note", "Removed Ring of Power from Harold")
      refute has_element?(view, "#wizard-hero-0 li", "Ring of Power")
    end

    test "keep changes nothing, a stale or wrong choice is refused in words", %{
      conn: conn,
      sid: sid
    } do
      load_places(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      raw = SessionStore.get(sid).save.raw

      view |> element("#wizard-place-hero-0-2") |> render_submit(%{"choice" => "keep"})
      assert has_element?(view, "#wizard-note", "Nothing to change")

      # a melee item for the misc place is refused by the save rules, not drawn from the page
      render_hook(view, "place_set", %{"place" => "hero:0:2", "choice" => "item:1"})
      assert has_element?(view, "#wizard-note", "place of its own kind")

      render_hook(view, "place_set", %{"place" => "hero:0:2", "choice" => "item:999"})
      assert has_element?(view, "#wizard-note", "no longer in the save")

      assert SessionStore.get(sid).save.raw == raw
    end
  end

  describe "adding a hero" do
    defp load_empty_heroes(sid) do
      empty = <<-1::little-signed-16>> <> :binary.copy(<<0>>, 26)

      raw =
        Enum.reduce(0..4, Mirror.WizardFixture.synthetic(), fn w, acc ->
          Mirror.WizardFixture.field(acc, w, 0x76, :binary.copy(empty, 6))
        end)

      SessionStore.put(sid, Mirror.SaveManager.normalize_state(%{save: %{raw: raw}}))
      raw
    end

    test "a hero is added from the drop-down in edit mode, as one undo step", %{
      conn: conn,
      sid: sid
    } do
      load_empty_heroes(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      refute has_element?(view, "#wizard-hero-add")
      view |> element("#wizard-edit-toggle") |> render_click()

      assert has_element?(view, "#wizard-hero-add option[value='31']", "Sir Harold")
      assert has_element?(view, "#wizard-hero-add option[value='0']", "Brax")
      before = SessionStore.get(sid)

      view |> element("#wizard-hero-add") |> render_submit(%{"type" => "31"})
      assert has_element?(view, "#wizard-note", "Added Sir Harold to Jafar's heroes")
      assert has_element?(view, "#wizard-hero-0", "Sir Harold")
      assert has_element?(view, "#wizard-hero-0", "level 1")
      assert has_element?(view, "#wizard-hero-0", "at 38, 21 Myrror")
      # he is in play now, so he is no longer offered
      refute has_element?(view, "#wizard-hero-add option[value='31']")

      added = SessionStore.get(sid)
      assert length(added.history.arcanus) == length(before.history.arcanus) + 1
      {undone, _} = Mirror.Editor.undo(added, :arcanus)
      assert undone.save.raw == before.save.raw
    end

    test "a hero already in play, or a bad number, is refused in words and changes nothing", %{
      conn: conn,
      sid: sid
    } do
      load_empty_heroes(sid)
      {:ok, view, _} = live(conn, ~p"/wizard/1")
      view |> element("#wizard-edit-toggle") |> render_click()
      view |> element("#wizard-hero-add") |> render_submit(%{"type" => "31"})
      raw = SessionStore.get(sid).save.raw

      render_hook(view, "hero_add", %{"type" => "31"})
      assert has_element?(view, "#wizard-note", "already in the game")

      render_hook(view, "hero_add", %{"type" => "99"})
      assert has_element?(view, "#wizard-note", "35 heroes")
      assert SessionStore.get(sid).save.raw == raw
    end
  end
end
