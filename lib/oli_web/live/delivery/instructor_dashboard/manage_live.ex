defmodule OliWeb.Delivery.InstructorDashboard.ManageLive do
  use OliWeb, :live_view

  alias OliWeb.Components.Delivery.InstructorDashboard

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
      <InstructorDashboard.main_layout {assigns}>
        <InstructorDashboard.manage {assigns} />
      </InstructorDashboard.main_layout>
    """
  end
end