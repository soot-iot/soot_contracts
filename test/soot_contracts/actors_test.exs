defmodule SootContracts.ActorsTest do
  use ExUnit.Case, async: true

  alias SootContracts.Actors
  alias SootContracts.Actors.System

  for part <- [:publisher, :public_reader] do
    test "system/1 builds a System actor with :#{part}" do
      part = unquote(part)
      assert %System{part: ^part, tenant_id: nil} = Actors.system(part)
    end
  end

  test "system/2 with binary tenant_id" do
    assert %System{tenant_id: "t-1"} = Actors.system(:publisher, "t-1")
  end

  test "system/2 with nil tenant" do
    assert %System{tenant_id: nil} = Actors.system(:publisher, nil)
  end

  test "system/2 with keyword opts" do
    assert %System{tenant_id: "t-x"} = Actors.system(:publisher, tenant_id: "t-x")
  end

  test "%System{} enforces :part" do
    assert_raise ArgumentError, fn -> struct!(System, []) end
  end
end
