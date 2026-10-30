using System.Buffers.Binary;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PcDoctor.Core.Ipc;

/// <summary>Length-prefixed (4-byte little-endian) UTF-8 JSON messages, at most 4 MiB each.</summary>
public static class PipeFraming
{
    public const int MaxMessageBytes = 4 * 1024 * 1024;

    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() },
    };

    public static async Task WriteAsync<T>(Stream stream, T message, CancellationToken ct)
    {
        var body = JsonSerializer.SerializeToUtf8Bytes(message, JsonOptions);
        if (body.Length > MaxMessageBytes)
        {
            throw new InvalidDataException("Message too large.");
        }
        var header = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(header, body.Length);
        await stream.WriteAsync(header, ct).ConfigureAwait(false);
        await stream.WriteAsync(body, ct).ConfigureAwait(false);
        await stream.FlushAsync(ct).ConfigureAwait(false);
    }

    /// <summary>Returns null at end of stream.</summary>
    public static async Task<byte[]?> ReadFrameAsync(Stream stream, CancellationToken ct)
    {
        var header = new byte[4];
        if (!await ReadExactlyOrEofAsync(stream, header, ct).ConfigureAwait(false))
        {
            return null;
        }
        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length is < 0 or > MaxMessageBytes)
        {
            throw new InvalidDataException($"Bad frame length {length}.");
        }
        var body = new byte[length];
        if (!await ReadExactlyOrEofAsync(stream, body, ct).ConfigureAwait(false))
        {
            throw new EndOfStreamException("Truncated frame.");
        }
        return body;
    }

    public static async Task<T?> ReadAsync<T>(Stream stream, CancellationToken ct)
    {
        var frame = await ReadFrameAsync(stream, ct).ConfigureAwait(false);
        return frame is null ? default : JsonSerializer.Deserialize<T>(frame, JsonOptions);
    }

    /// <summary>
    /// Parses a request. Anything that is not exactly one of the known request types (unknown op,
    /// missing discriminator, malformed JSON) yields null and the Broker refuses it.
    /// </summary>
    public static BrokerRequest? TryParseRequest(byte[] frame, out Guid requestId)
    {
        requestId = Guid.Empty;
        try
        {
            using (var doc = JsonDocument.Parse(frame))
            {
                if (doc.RootElement.TryGetProperty("requestId", out var id) && id.TryGetGuid(out var g))
                {
                    requestId = g;
                }
            }
            return JsonSerializer.Deserialize<BrokerRequest>(frame, JsonOptions);
        }
        catch (JsonException)
        {
            return null;
        }
        catch (NotSupportedException)
        {
            return null;
        }
    }

    private static async Task<bool> ReadExactlyOrEofAsync(Stream stream, byte[] buffer, CancellationToken ct)
    {
        var read = 0;
        while (read < buffer.Length)
        {
            var n = await stream.ReadAsync(buffer.AsMemory(read), ct).ConfigureAwait(false);
            if (n == 0)
            {
                return read == 0 ? false : throw new EndOfStreamException("Truncated frame.");
            }
            read += n;
        }
        return true;
    }
}
