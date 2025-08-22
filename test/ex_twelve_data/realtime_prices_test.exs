defmodule ExTwelveData.RealtimePricesTest do
  use ExUnit.Case

  alias ExTwelveData.RealTimePrices

  @moduletag :capture_log

  doctest RealTimePrices

  test "module exists" do
    assert is_list(RealTimePrices.module_info())
  end

  defmodule SamplePriceUpdateHandler do
    @behaviour RealTimePrices.Handler

    @impl true
    def handle_price_update(price) do
      assert price.event == "price"
    end
  end

  defmodule TestPriceCapture do
    @behaviour RealTimePrices.Handler
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    @impl true
    def handle_price_update(price) do
      Agent.update(__MODULE__, fn prices -> [price | prices] end)
      :ok
    end

    def get_captured_prices do
      Agent.get(__MODULE__, & &1)
    end

    def clear_prices do
      Agent.update(__MODULE__, fn _ -> [] end)
    end
  end

  test "handle price update" do
    RealTimePrices.handle_frame(
      {:text, ~s({"event": "price"})},
      %{handler: SamplePriceUpdateHandler}
    )
  end

  test "handle subscribe-status error with messages field" do
    {result, _state} = RealTimePrices.handle_frame(
      {:text, ~s({"event": "subscribe-status", "status": "error", "messages": ["Cant parse message"]})},
      %{handler: SamplePriceUpdateHandler}
    )
    
    assert result === :ok
  end

  test "handle subscribe-status success with success/fails arrays" do
    success_response = ~s({
      "event": "subscribe-status",
      "status": "ok",
      "success": [
        {"symbol": "AAPL", "exchange": "NASDAQ", "country": "United States", "type": "Common Stock"}
      ],
      "fails": []
    })
    
    {result, _state} = RealTimePrices.handle_frame(
      {:text, success_response},
      %{handler: SamplePriceUpdateHandler}
    )
    
    assert result === :ok
  end

  test "handle unsubscribe-status error with messages field" do
    {result, _state} = RealTimePrices.handle_frame(
      {:text, ~s({"event": "unsubscribe-status", "status": "error", "messages": ["Symbol not found"]})},
      %{handler: SamplePriceUpdateHandler}
    )
    
    assert result === :ok
  end

  test "handle reset-status error with messages field" do
    {result, _state} = RealTimePrices.handle_frame(
      {:text, ~s({"event": "reset-status", "status": "error", "messages": ["Reset failed"]})},
      %{handler: SamplePriceUpdateHandler}
    )
    
    assert result === :ok
  end

  test "validate price update format with real data" do
    TestPriceCapture.start_link()
    TestPriceCapture.clear_prices()

    # Simulate a real BTC/USD price update based on Twelve Data format
    price_update = ~s({
      "event": "price",
      "symbol": "BTC/USD",
      "currency": "USD",
      "currency_base": "Bitcoin",
      "currency_quote": "US Dollar",
      "type": "Physical Currency",
      "timestamp": 1692720000,
      "price": 26500.50,
      "bid": 26500.25,
      "ask": 26500.75
    })

    {result, _state} = RealTimePrices.handle_frame(
      {:text, price_update},
      %{handler: TestPriceCapture}
    )

    assert result === :ok
    
    captured_prices = TestPriceCapture.get_captured_prices()
    assert length(captured_prices) === 1
    
    price = List.first(captured_prices)
    assert price.event === "price"
    assert price.symbol === "BTC/USD"
    assert price.currency === "USD"
    assert price.price === 26500.50
    assert price.timestamp === 1692720000
    assert Map.has_key?(price, :bid)
    assert Map.has_key?(price, :ask)
  end

  test "validate stock price update format" do
    TestPriceCapture.start_link()
    TestPriceCapture.clear_prices()

    # Simulate a stock price update (AAPL format)
    stock_update = ~s({
      "event": "price",
      "symbol": "AAPL",
      "currency": "USD",
      "exchange": "NASDAQ",
      "type": "Common Stock",
      "timestamp": 1692720000,
      "price": 175.25,
      "day_volume": 45123456
    })

    {result, _state} = RealTimePrices.handle_frame(
      {:text, stock_update},
      %{handler: TestPriceCapture}
    )

    assert result === :ok
    
    captured_prices = TestPriceCapture.get_captured_prices()
    assert length(captured_prices) === 1
    
    price = List.first(captured_prices)
    assert price.event === "price"
    assert price.symbol === "AAPL"
    assert price.currency === "USD"
    assert price.exchange === "NASDAQ"
    assert price.price === 175.25
    assert price.day_volume === 45123456
  end
end
