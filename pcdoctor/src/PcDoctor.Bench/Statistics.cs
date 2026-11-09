namespace PcDoctor.Bench;

public enum Direction { LowerIsBetter, HigherIsBetter }

public enum Verdict { Improved, Regressed, NoSignificantChange, InsufficientData }

public sealed record Summary(int Count, double Median, double Q1, double Q3, double Mean, double StdDev)
{
    public double Iqr => Q3 - Q1;
    public double RelativeStdDev => Mean == 0 ? 0 : StdDev / Math.Abs(Mean);
}

public sealed record Comparison(
    Verdict Verdict,
    Summary Before,
    Summary After,
    double RelativeChange,
    double PValue,
    double CiLow,
    double CiHigh,
    double MinimumEffect);

/// <summary>
/// Benchmark statistics (DESIGN M12): median and IQR, a two-sided Mann-Whitney U test, a bootstrap
/// 95% CI for the relative change in medians, and a minimum practical effect. Both significance and
/// size are required before saying "improved" or "regressed"; otherwise the honest answer is
/// "no significant change (within measurement noise)".
/// </summary>
public static class Statistics
{
    public static Summary Summarize(IReadOnlyList<double> values)
    {
        if (values.Count == 0)
        {
            return new Summary(0, double.NaN, double.NaN, double.NaN, double.NaN, double.NaN);
        }
        var sorted = values.OrderBy(v => v).ToArray();
        var mean = sorted.Average();
        var sd = sorted.Length > 1 ? Math.Sqrt(sorted.Sum(v => (v - mean) * (v - mean)) / (sorted.Length - 1)) : 0;
        return new Summary(sorted.Length, Quantile(sorted, 0.5), Quantile(sorted, 0.25), Quantile(sorted, 0.75), mean, sd);
    }

    /// <summary>Linear interpolation between closest ranks (type 7, the R/NumPy default).</summary>
    public static double Quantile(double[] sorted, double q)
    {
        if (sorted.Length == 1)
        {
            return sorted[0];
        }
        var h = (sorted.Length - 1) * q;
        var lo = (int)Math.Floor(h);
        var hi = Math.Min(lo + 1, sorted.Length - 1);
        return sorted[lo] + (h - lo) * (sorted[hi] - sorted[lo]);
    }

    public static double Quantile(IEnumerable<double> values, double q) => Quantile(values.OrderBy(v => v).ToArray(), q);

    /// <summary>Two-sided p-value, normal approximation with tie and continuity correction.</summary>
    public static double MannWhitneyP(IReadOnlyList<double> a, IReadOnlyList<double> b)
    {
        int n1 = a.Count, n2 = b.Count, n = n1 + n2;
        if (n1 == 0 || n2 == 0)
        {
            return 1;
        }
        var all = a.Select(v => (v, g: 0)).Concat(b.Select(v => (v, g: 1))).OrderBy(x => x.v).ToArray();
        var ranks = new double[n];
        double tieSum = 0;
        for (var i = 0; i < n;)
        {
            var j = i;
            while (j + 1 < n && all[j + 1].v == all[i].v)
            {
                j++;
            }
            var avg = (i + j + 2) / 2.0;
            for (var k = i; k <= j; k++)
            {
                ranks[k] = avg;
            }
            var t = j - i + 1;
            tieSum += t * t * t - t;
            i = j + 1;
        }
        var r1 = Enumerable.Range(0, n).Where(i => all[i].g == 0).Sum(i => ranks[i]);
        var u1 = r1 - n1 * (n1 + 1) / 2.0;
        var mu = n1 * n2 / 2.0;
        var sigma = Math.Sqrt(n1 * n2 / 12.0 * (n + 1 - tieSum / (n * (n - 1.0))));
        if (sigma == 0)
        {
            return 1;
        }
        var z = (Math.Abs(u1 - mu) - 0.5) / sigma;
        return Math.Clamp(2 * (1 - NormalCdf(Math.Max(0, z))), 0, 1);
    }

    /// <summary>Standard normal CDF (Abramowitz and Stegun 7.1.26 erf, error below 1.5e-7).</summary>
    public static double NormalCdf(double z)
    {
        var x = Math.Abs(z) / Math.Sqrt(2);
        var t = 1 / (1 + 0.3275911 * x);
        var erf = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.Exp(-x * x);
        return z >= 0 ? (1 + erf) / 2 : (1 - erf) / 2;
    }

    /// <summary>Percentile bootstrap CI of (median(after) − median(before)) / median(before). Seeded: same data, same answer.</summary>
    public static (double Low, double High) BootstrapRelativeChange(IReadOnlyList<double> before, IReadOnlyList<double> after, int iterations = 2000, int seed = 20261109)
    {
        var rng = new Random(seed);
        var diffs = new double[iterations];
        var b = new double[before.Count];
        var a = new double[after.Count];
        for (var i = 0; i < iterations; i++)
        {
            for (var k = 0; k < b.Length; k++)
            {
                b[k] = before[rng.Next(before.Count)];
            }
            for (var k = 0; k < a.Length; k++)
            {
                a[k] = after[rng.Next(after.Count)];
            }
            Array.Sort(b);
            Array.Sort(a);
            var mb = Quantile(b, 0.5);
            diffs[i] = mb == 0 ? 0 : (Quantile(a, 0.5) - mb) / Math.Abs(mb);
        }
        Array.Sort(diffs);
        return (Quantile(diffs, 0.025), Quantile(diffs, 0.975));
    }

    public static Comparison Compare(IReadOnlyList<double> before, IReadOnlyList<double> after, Direction direction, double minimumEffect = 0.03)
    {
        var sb = Summarize(before);
        var sa = Summarize(after);
        if (before.Count < 3 || after.Count < 3)
        {
            return new Comparison(Verdict.InsufficientData, sb, sa, double.NaN, 1, double.NaN, double.NaN, minimumEffect);
        }
        var rel = sb.Median == 0 ? 0 : (sa.Median - sb.Median) / Math.Abs(sb.Median);
        var p = MannWhitneyP(before, after);
        var (lo, hi) = BootstrapRelativeChange(before, after);
        // The whole 95% interval must clear half the practical floor, not just zero: with 5-10 noisy runs a
        // CI that barely excludes zero still produces false "improved" verdicts on unchanged systems.
        var margin = minimumEffect / 2;
        var significant = p < 0.05 && (lo > margin || hi < -margin);
        var practical = Math.Abs(rel) >= minimumEffect;
        var verdict = !(significant && practical)
            ? Verdict.NoSignificantChange
            : (rel < 0) == (direction == Direction.LowerIsBetter) ? Verdict.Improved : Verdict.Regressed;
        return new Comparison(verdict, sb, sa, rel, p, lo, hi, minimumEffect);
    }
}

/// <summary>Warm-up runs are discarded; measuring continues until the relative SD is at most 3.5% or 10 runs (DESIGN M12).</summary>
public static class AdaptiveRunner
{
    public static async Task<IReadOnlyList<double>> RunAsync(Func<CancellationToken, Task<double>> measure, CancellationToken ct,
        int warmups = 2, int minRuns = 5, int maxRuns = 10, double targetRsd = 0.035, Action<int, double>? onRun = null)
    {
        for (var i = 0; i < warmups; i++)
        {
            await measure(ct).ConfigureAwait(false);
        }
        var values = new List<double>();
        while (values.Count < maxRuns)
        {
            ct.ThrowIfCancellationRequested();
            var v = await measure(ct).ConfigureAwait(false);
            values.Add(v);
            onRun?.Invoke(values.Count, v);
            if (values.Count >= minRuns && Statistics.Summarize(values).RelativeStdDev <= targetRsd)
            {
                break;
            }
        }
        return values;
    }
}
