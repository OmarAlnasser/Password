using System.IO;
using System.Net.Http;
using Anthropic;
using Anthropic.Exceptions;
using Anthropic.Models.Messages;

namespace PcDoctor.App.Services;

public enum DriverAiOutcome { Answered, BadKey, Busy, Declined, Failed }

public sealed record DriverAiResult(DriverAiOutcome Outcome, string Text);

/// <summary>
/// Optional AI research for the driver advisor, with the user's own key. It runs only after the user has seen exactly
/// what is sent and agreed. It reads official maker sites and Microsoft only, and it never downloads or installs anything:
/// the answer is text for the user to check on the official page.
/// </summary>
public static class DriverAi
{
    private const string Model = "claude-opus-5-5";

    public static async Task<DriverAiResult> AskAsync(string apiKey, string prompt, IReadOnlyList<string> allowedDomains, CancellationToken ct)
    {
        try
        {
            // One client per question, released when the answer is in: nothing is kept alive between questions.
            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(4) };
            var client = new AnthropicClient { ApiKey = apiKey, HttpClient = http };
            var response = await client.Messages.Create(new MessageCreateParams
            {
                Model = Model,
                MaxTokens = 8000,
                Tools = [new ToolUnion(new WebSearchTool20260209 { AllowedDomains = [.. allowedDomains], MaxUses = 8 })],
                Messages = [new UserMessageParam { Content = prompt }],
            }, cancellationToken: ct).ConfigureAwait(false);

            if (response.StopReason is { } stop && stop == StopReason.Refusal)
            {
                return new DriverAiResult(DriverAiOutcome.Declined, "");
            }
            var text = string.Join("\n", response.Content.Select(b => b.Value).OfType<TextBlock>().Select(t => t.Text)).Trim();
            return text.Length == 0 ? new DriverAiResult(DriverAiOutcome.Failed, "") : new DriverAiResult(DriverAiOutcome.Answered, text);
        }
        catch (AnthropicUnauthorizedException)
        {
            return new DriverAiResult(DriverAiOutcome.BadKey, "");
        }
        catch (AnthropicRateLimitException)
        {
            return new DriverAiResult(DriverAiOutcome.Busy, "");
        }
        catch (Exception ex) when (ex is AnthropicException or HttpRequestException or TaskCanceledException or IOException)
        {
            return new DriverAiResult(DriverAiOutcome.Failed, ex.Message);
        }
    }
}
