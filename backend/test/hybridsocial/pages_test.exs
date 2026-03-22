defmodule Hybridsocial.PagesTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Pages

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_user(handle, email) do
    {:ok, identity} =
      Hybridsocial.Accounts.register_user(%{
        "handle" => handle,
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    identity
  end

  defp create_test_page(owner, handle) do
    {:ok, page} =
      Pages.create_page(owner.id, %{
        "handle" => handle,
        "display_name" => "Test Page #{handle}",
        "bio" => "A test page",
        "website" => "https://example.com",
        "category" => "tech"
      })

    page
  end

  # ---------------------------------------------------------------------------
  # Page lifecycle
  # ---------------------------------------------------------------------------

  describe "create_page/2" do
    test "creates an organization page" do
      owner = create_user("pg_owner1", "pg_owner1@example.com")

      {:ok, page} =
        Pages.create_page(owner.id, %{
          "handle" => "my_page",
          "display_name" => "My Page",
          "bio" => "Cool page",
          "website" => "https://example.com",
          "category" => "tech"
        })

      assert page.handle == "my_page"
      assert page.type == "organization"
      assert page.display_name == "My Page"
      assert page.organization.owner_id == owner.id
      assert page.organization.website == "https://example.com"
      assert page.organization.category == "tech"
    end

    test "fails with duplicate handle" do
      owner = create_user("pg_owner2", "pg_owner2@example.com")
      _page = create_test_page(owner, "dup_handle")

      assert {:error, _changeset} =
               Pages.create_page(owner.id, %{
                 "handle" => "dup_handle",
                 "display_name" => "Duplicate"
               })
    end
  end

  describe "get_page/1" do
    test "returns the page with organization" do
      owner = create_user("pg_get1", "pg_get1@example.com")
      page = create_test_page(owner, "get_page1")

      result = Pages.get_page(page.id)
      assert result.id == page.id
      assert result.organization != nil
    end

    test "returns nil for non-existent page" do
      assert Pages.get_page(Ecto.UUID.generate()) == nil
    end

    test "returns nil for deleted page" do
      owner = create_user("pg_get2", "pg_get2@example.com")
      page = create_test_page(owner, "get_page2")
      {:ok, _} = Pages.delete_page(page.id, owner.id)

      assert Pages.get_page(page.id) == nil
    end
  end

  describe "update_page/3" do
    test "owner can update a page" do
      owner = create_user("pg_upd1", "pg_upd1@example.com")
      page = create_test_page(owner, "upd_page1")

      {:ok, updated} =
        Pages.update_page(page.id, owner.id, %{
          "display_name" => "Updated Name",
          "website" => "https://updated.com"
        })

      assert updated.display_name == "Updated Name"
      assert updated.organization.website == "https://updated.com"
    end

    test "admin can update a page" do
      owner = create_user("pg_upd2", "pg_upd2@example.com")
      admin = create_user("pg_upd3", "pg_upd3@example.com")
      page = create_test_page(owner, "upd_page2")
      {:ok, _} = Pages.add_role(page.id, owner.id, admin.id, "admin")

      {:ok, updated} =
        Pages.update_page(page.id, admin.id, %{"display_name" => "Admin Updated"})

      assert updated.display_name == "Admin Updated"
    end

    test "non-authorized user cannot update" do
      owner = create_user("pg_upd4", "pg_upd4@example.com")
      rando = create_user("pg_upd5", "pg_upd5@example.com")
      page = create_test_page(owner, "upd_page3")

      assert {:error, :forbidden} =
               Pages.update_page(page.id, rando.id, %{"display_name" => "Hacked"})
    end
  end

  describe "delete_page/2" do
    test "owner can soft delete a page" do
      owner = create_user("pg_del1", "pg_del1@example.com")
      page = create_test_page(owner, "del_page1")

      {:ok, deleted} = Pages.delete_page(page.id, owner.id)
      assert deleted.deleted_at != nil
    end

    test "non-owner cannot delete" do
      owner = create_user("pg_del2", "pg_del2@example.com")
      rando = create_user("pg_del3", "pg_del3@example.com")
      page = create_test_page(owner, "del_page2")

      assert {:error, :forbidden} = Pages.delete_page(page.id, rando.id)
    end
  end

  describe "list_pages/1" do
    test "lists organization pages" do
      owner = create_user("pg_list1", "pg_list1@example.com")
      _page = create_test_page(owner, "list_page1")

      pages = Pages.list_pages()
      assert length(pages) >= 1
      assert Enum.all?(pages, fn p -> p.type == "organization" end)
    end
  end

  describe "pages_for_owner/1" do
    test "returns only pages owned by the given identity" do
      owner1 = create_user("pg_pfo1", "pg_pfo1@example.com")
      owner2 = create_user("pg_pfo2", "pg_pfo2@example.com")
      _page1 = create_test_page(owner1, "pfo_page1")
      _page2 = create_test_page(owner2, "pfo_page2")

      pages = Pages.pages_for_owner(owner1.id)
      assert length(pages) == 1
      assert hd(pages).handle == "pfo_page1"
    end
  end

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  describe "add_role/4" do
    test "owner can add a role" do
      owner = create_user("pg_ar1", "pg_ar1@example.com")
      user = create_user("pg_ar2", "pg_ar2@example.com")
      page = create_test_page(owner, "ar_page1")

      {:ok, role} = Pages.add_role(page.id, owner.id, user.id, "editor")
      assert role.role == "editor"
      assert role.identity_id == user.id
    end

    test "admin can add a role" do
      owner = create_user("pg_ar3", "pg_ar3@example.com")
      admin = create_user("pg_ar4", "pg_ar4@example.com")
      user = create_user("pg_ar5", "pg_ar5@example.com")
      page = create_test_page(owner, "ar_page2")
      {:ok, _} = Pages.add_role(page.id, owner.id, admin.id, "admin")

      {:ok, role} = Pages.add_role(page.id, admin.id, user.id, "moderator")
      assert role.role == "moderator"
    end

    test "non-admin cannot add a role" do
      owner = create_user("pg_ar6", "pg_ar6@example.com")
      rando = create_user("pg_ar7", "pg_ar7@example.com")
      user = create_user("pg_ar8", "pg_ar8@example.com")
      page = create_test_page(owner, "ar_page3")

      assert {:error, :forbidden} = Pages.add_role(page.id, rando.id, user.id, "editor")
    end
  end

  describe "remove_role/3" do
    test "owner can remove a role" do
      owner = create_user("pg_rr1", "pg_rr1@example.com")
      user = create_user("pg_rr2", "pg_rr2@example.com")
      page = create_test_page(owner, "rr_page1")
      {:ok, role} = Pages.add_role(page.id, owner.id, user.id, "editor")

      {:ok, _} = Pages.remove_role(page.id, owner.id, role.id)
      assert Pages.get_roles(page.id) == []
    end
  end

  describe "get_roles/1" do
    test "lists roles for a page" do
      owner = create_user("pg_gr1", "pg_gr1@example.com")
      user = create_user("pg_gr2", "pg_gr2@example.com")
      page = create_test_page(owner, "gr_page1")
      {:ok, _} = Pages.add_role(page.id, owner.id, user.id, "editor")

      roles = Pages.get_roles(page.id)
      assert length(roles) == 1
      assert hd(roles).role == "editor"
    end
  end

  describe "has_role?/3" do
    test "returns true if identity has the role" do
      owner = create_user("pg_hr1", "pg_hr1@example.com")
      user = create_user("pg_hr2", "pg_hr2@example.com")
      page = create_test_page(owner, "hr_page1")
      {:ok, _} = Pages.add_role(page.id, owner.id, user.id, "admin")

      assert Pages.has_role?(page.id, user.id, ["admin"])
    end

    test "returns false if identity does not have the role" do
      owner = create_user("pg_hr3", "pg_hr3@example.com")
      user = create_user("pg_hr4", "pg_hr4@example.com")
      page = create_test_page(owner, "hr_page2")

      refute Pages.has_role?(page.id, user.id, ["admin"])
    end
  end

  describe "can_edit?/2" do
    test "owner can edit" do
      owner = create_user("pg_ce1", "pg_ce1@example.com")
      page = create_test_page(owner, "ce_page1")

      assert Pages.can_edit?(page.id, owner.id)
    end

    test "admin can edit" do
      owner = create_user("pg_ce2", "pg_ce2@example.com")
      admin = create_user("pg_ce3", "pg_ce3@example.com")
      page = create_test_page(owner, "ce_page2")
      {:ok, _} = Pages.add_role(page.id, owner.id, admin.id, "admin")

      assert Pages.can_edit?(page.id, admin.id)
    end

    test "editor can edit" do
      owner = create_user("pg_ce4", "pg_ce4@example.com")
      editor = create_user("pg_ce5", "pg_ce5@example.com")
      page = create_test_page(owner, "ce_page3")
      {:ok, _} = Pages.add_role(page.id, owner.id, editor.id, "editor")

      assert Pages.can_edit?(page.id, editor.id)
    end

    test "random user cannot edit" do
      owner = create_user("pg_ce6", "pg_ce6@example.com")
      rando = create_user("pg_ce7", "pg_ce7@example.com")
      page = create_test_page(owner, "ce_page4")

      refute Pages.can_edit?(page.id, rando.id)
    end
  end

  # ---------------------------------------------------------------------------
  # Branding
  # ---------------------------------------------------------------------------

  describe "get_branding/1" do
    test "returns nil when no branding exists" do
      owner = create_user("pg_gb1", "pg_gb1@example.com")
      page = create_test_page(owner, "gb_page1")

      assert Pages.get_branding(page.id) == nil
    end
  end

  describe "update_branding/3" do
    test "creates branding when none exists" do
      owner = create_user("pg_ub1", "pg_ub1@example.com")
      page = create_test_page(owner, "ub_page1")

      {:ok, branding} =
        Pages.update_branding(page.id, owner.id, %{
          "theme_color" => "#ff0000",
          "logo_url" => "https://example.com/logo.png"
        })

      assert branding.theme_color == "#ff0000"
      assert branding.logo_url == "https://example.com/logo.png"
    end

    test "updates existing branding" do
      owner = create_user("pg_ub2", "pg_ub2@example.com")
      page = create_test_page(owner, "ub_page2")

      {:ok, _} =
        Pages.update_branding(page.id, owner.id, %{"theme_color" => "#ff0000"})

      {:ok, updated} =
        Pages.update_branding(page.id, owner.id, %{"theme_color" => "#00ff00"})

      assert updated.theme_color == "#00ff00"
    end

    test "sanitizes custom_css" do
      owner = create_user("pg_ub3", "pg_ub3@example.com")
      page = create_test_page(owner, "ub_page3")

      {:ok, branding} =
        Pages.update_branding(page.id, owner.id, %{
          "custom_css" => "@import url('evil.css'); body { color: red; } div { background: url(evil.png); } expression(alert(1)) javascript: alert(1)"
        })

      refute branding.custom_css =~ "@import"
      refute branding.custom_css =~ "url("
      refute branding.custom_css =~ "expression("
      refute branding.custom_css =~ "javascript:"
      assert branding.custom_css =~ "body { color: red; }"
    end

    test "non-admin cannot update branding" do
      owner = create_user("pg_ub4", "pg_ub4@example.com")
      rando = create_user("pg_ub5", "pg_ub5@example.com")
      page = create_test_page(owner, "ub_page4")

      assert {:error, :forbidden} =
               Pages.update_branding(page.id, rando.id, %{"theme_color" => "#ff0000"})
    end
  end
end
