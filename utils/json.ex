defmodule YuurisanJSON do
  @moduledoc false

  def decode(binary) when is_binary(binary) do
    try do
      {value, rest} = parse_value(skip_ws(binary))

      case skip_ws(rest) do
        "" -> {:ok, value}
        _ -> {:error, "unexpected trailing data"}
      end
    rescue
      _ -> {:error, "invalid json"}
    catch
      _, _ -> {:error, "invalid json"}
    end
  end

  def decode(_), do: {:error, "invalid json"}

  def encode(value) when is_map(value) do
    inner =
      value
      |> Enum.map(fn {key, item} -> encode(to_string(key)) <> ":" <> encode(item) end)
      |> Enum.join(",")

    "{" <> inner <> "}"
  end

  def encode(value) when is_list(value) do
    "[" <> (value |> Enum.map(&encode/1) |> Enum.join(",")) <> "]"
  end

  def encode(value) when is_binary(value), do: quote_string(value)
  def encode(value) when is_integer(value), do: Integer.to_string(value)
  def encode(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(nil), do: "null"
  def encode(value), do: encode(to_string(value))

  def get(map, key, default \\ nil)

  def get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  def get(_, _, default), do: default

  defp quote_string(value) do
    escaped =
      for <<char::utf8 <- value>>, into: "" do
        case char do
          ?" -> "\\\""
          ?\\ -> "\\\\"
          ?\n -> "\\n"
          ?\r -> "\\r"
          ?\t -> "\\t"
          small when small < 0x20 -> "\\u" <> String.pad_leading(Integer.to_string(small, 16), 4, "0")
          other -> <<other::utf8>>
        end
      end

    "\"" <> escaped <> "\""
  end

  defp skip_ws(<<char, rest::binary>>) when char in [32, 9, 10, 13], do: skip_ws(rest)
  defp skip_ws(binary), do: binary

  defp parse_value(<<"{", rest::binary>>), do: parse_object(skip_ws(rest), %{})
  defp parse_value(<<"[", rest::binary>>), do: parse_array(skip_ws(rest), [])
  defp parse_value(<<"\"", rest::binary>>), do: parse_string(rest, [])
  defp parse_value(<<"true", rest::binary>>), do: {true, rest}
  defp parse_value(<<"false", rest::binary>>), do: {false, rest}
  defp parse_value(<<"null", rest::binary>>), do: {nil, rest}
  defp parse_value(binary), do: parse_number(binary)

  defp parse_object(<<"}", rest::binary>>, acc), do: {acc, rest}

  defp parse_object(<<"\"", rest::binary>>, acc) do
    {key, rest} = parse_string(rest, [])
    <<":", rest::binary>> = skip_ws(rest)
    {value, rest} = parse_value(skip_ws(rest))
    acc = Map.put(acc, key, value)

    case skip_ws(rest) do
      <<",", rest::binary>> -> parse_object(skip_ws(rest), acc)
      <<"}", rest::binary>> -> {acc, rest}
    end
  end

  defp parse_array(<<"]", rest::binary>>, acc), do: {Enum.reverse(acc), rest}

  defp parse_array(binary, acc) do
    {value, rest} = parse_value(binary)

    case skip_ws(rest) do
      <<",", rest::binary>> -> parse_array(skip_ws(rest), [value | acc])
      <<"]", rest::binary>> -> {Enum.reverse([value | acc]), rest}
    end
  end

  defp parse_string(<<"\"", rest::binary>>, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  end

  defp parse_string(<<"\\", char, rest::binary>>, acc) do
    case char do
      ?" -> parse_string(rest, ["\"" | acc])
      ?\\ -> parse_string(rest, ["\\" | acc])
      ?/ -> parse_string(rest, ["/" | acc])
      ?b -> parse_string(rest, [<<8>> | acc])
      ?f -> parse_string(rest, [<<12>> | acc])
      ?n -> parse_string(rest, ["\n" | acc])
      ?r -> parse_string(rest, ["\r" | acc])
      ?t -> parse_string(rest, ["\t" | acc])
      ?u -> parse_unicode(rest, acc)
    end
  end

  defp parse_string(<<char::utf8, rest::binary>>, acc) do
    parse_string(rest, [<<char::utf8>> | acc])
  end

  defp parse_unicode(<<hex::binary-size(4), rest::binary>>, acc) do
    code = String.to_integer(hex, 16)

    if code >= 0xD800 and code <= 0xDBFF do
      case rest do
        <<"\\u", low::binary-size(4), rest::binary>> ->
          low_code = String.to_integer(low, 16)
          point = 0x10000 + (code - 0xD800) * 0x400 + (low_code - 0xDC00)
          parse_string(rest, [<<point::utf8>> | acc])

        _ ->
          parse_string(rest, ["?" | acc])
      end
    else
      parse_string(rest, [<<code::utf8>> | acc])
    end
  end

  defp parse_number(binary) do
    {token, rest} = take_number(binary, [])
    text = token |> Enum.reverse() |> IO.iodata_to_binary()

    cond do
      text == "" ->
        raise "number expected"

      String.contains?(text, [".", "e", "E"]) ->
        case Float.parse(text) do
          {value, ""} -> {value, rest}
          _ -> raise "number expected"
        end

      true ->
        {String.to_integer(text), rest}
    end
  end

  defp take_number(<<char, rest::binary>>, acc)
       when char in ?0..?9 or char in [?-, ?+, ?., ?e, ?E] do
    take_number(rest, [<<char>> | acc])
  end

  defp take_number(binary, acc), do: {acc, binary}
end
