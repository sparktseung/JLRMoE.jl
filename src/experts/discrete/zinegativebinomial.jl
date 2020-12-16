struct ZINegativeBinomialExpert{T<:Real} <: ZIDiscreteExpert
    p0::T
    n::T
    p::T
    ZINegativeBinomialExpert{T}(p0, n, p) where {T<:Real} = new{T}(p0, n, p)
end

function ZINegativeBinomialExpert(p0::T, n::T, p::T; check_args=true) where {T <: Real}
    check_args && @check_args(ZINegativeBinomialExpert, 0 <= p0 <= 1 && 0 <= p <= 1 && n > zero(n))
    return ZINegativeBinomialExpert{T}(p0, n, p)
end

## Outer constructors
ZINegativeBinomialExpert(p0::Real, n::Real, p::Real) = ZINegativeBinomialExpert(promote(p0, n, p)...)
ZINegativeBinomialExpert(p0::Integer, n::Integer, p::Integer) = ZINegativeBinomialExpert(float(p0), n, float(p))
ZINegativeBinomialExpert() = ZINegativeBinomialExpert(0.50, 1, 0.50)

## Conversion
function convert(::Type{ZINegativeBinomialExpert{T}}, p0::S, n::S, p::S) where {T <: Real, S <: Real}
    ZINegativeBinomialExpert(T(p0), T(n), T(p))
end
function convert(::Type{ZINegativeBinomialExpert{T}}, d::ZINegativeBinomialExpert{S}) where {T <: Real, S <: Real}
    ZINegativeBinomialExpert(T(d.p0), T(d.n), T(d.p), check_args=false)
end
copy(d::ZINegativeBinomialExpert) = ZINegativeBinomialExpert(d.p0, d.n, d.p, check_args=false)

## Loglikelihood of Expoert
logpdf(d::ZINegativeBinomialExpert, x...) = isinf(x...) ? -Inf : Distributions.logpdf.(Distributions.NegativeBinomial(d.n, d.p), x...)
pdf(d::ZINegativeBinomialExpert, x...) = isinf(x...) ? 0.0 : Distributions.pdf.(Distributions.NegativeBinomial(d.n, d.p), x...)
logcdf(d::ZINegativeBinomialExpert, x...) = isinf(x...) ? 0.0 : Distributions.logcdf.(Distributions.NegativeBinomial(d.n, d.p), x...)
cdf(d::ZINegativeBinomialExpert, x...) = isinf(x...) ? 1.0 : Distributions.cdf.(Distributions.NegativeBinomial(d.n, d.p), x...)

## Parameters
params(d::ZINegativeBinomialExpert) = (d.p0, d.n, d.p)
function params_init(y, d::ZINegativeBinomialExpert)
    pos_idx = (y .> 0.0)
    μ, σ2 = mean(y[pos_idx]), var(y[pos_idx])
    p_init = μ / σ2
    n_init = μ*p_init/(1-p_init)
    p0_init = 1 - mean(y)/μ
    try 
        ZINegativeBinomialExpert(p0_init, n_init, p_init) 
    catch; 
        ZINegativeBinomialExpert() 
    end
end

## Simululation
sim_expert(d::ZINegativeBinomialExpert, sample_size) = (1 .- Distributions.rand(Distributions.Bernoulli(d.p0), sample_size)) .* Distributions.rand(Distributions.NegativeBinomial(d.n, d.p), sample_size)

## penalty
penalty_init(d::ZINegativeBinomialExpert) = [2.0 10.0]
no_penalty_init(d::ZINegativeBinomialExpert) = [1.0 Inf]
penalize(d::ZINegativeBinomialExpert, p) = (p[1]-1)*log(d.n) - d.n/p[2]

## statistics
mean(d::ZINegativeBinomialExpert) = (1-d.p0)*mean(Distributions.NegativeBinomial(d.n, d.p))
var(d::ZINegativeBinomialExpert) = (1-d.p0)*var(Distributions.NegativeBinomial(d.n, d.p)) + + d.p0*(1-d.p0)*(mean(Distributions.NegativeBinomial(d.n, d.p)))^2
quantile(d::ZINegativeBinomialExpert, p) = p <= d.p0 ? 0.0 :  quantile(Distributions.NegativeBinomial(d.n, d.p), p-d.p0)

## EM: M-Step
function EM_M_expert(d::ZINegativeBinomialExpert,
                    tl, yl, yu, tu,
                    expert_ll_pos,
                    expert_tn_pos,
                    expert_tn_bar_pos,
                    z_e_obs, z_e_lat, k_e;
                    penalty = true, pen_pararms_jk = [2.0 1.0])

    # Old parameters
    p_old = d.p0

    # Update zero probability
    z_zero_e_obs = z_e_obs .* EM_E_z_zero_obs(yl, p_old, expert_ll_pos)
    z_pos_e_obs = z_e_obs .- z_zero_e_obs
    z_zero_e_lat = z_e_lat .* EM_E_z_zero_lat(tl, p_old, expert_tn_bar_pos)
    z_pos_e_lat = z_e_lat .- z_zero_e_lat
    p_new = EM_M_zero(z_zero_e_obs, z_pos_e_obs, z_zero_e_lat, z_pos_e_lat, k_e)

    # Update parameters: call its positive part
    tmp_exp = NegativeBinomialExpert(d.n, d.p)
    tmp_update = EM_M_expert(tmp_exp,
                            tl, yl, yu, tu,
                            expert_ll_pos,
                            expert_tn_pos,
                            expert_tn_bar_pos,
                            # z_e_obs, z_e_lat, k_e,
                            z_pos_e_obs, z_pos_e_lat, k_e,
                            penalty = penalty, pen_pararms_jk = pen_pararms_jk)

    return ZINegativeBinomialExpert(p_new, tmp_update.n, tmp_update.p)

end

## EM: M-Step, exact observations
function EM_M_expert_exact(d::ZINegativeBinomialExpert,
                    ye,
                    expert_ll_pos,
                    z_e_obs; 
                    penalty = true, pen_pararms_jk = [2.0 1.0])

    # Old parameters
    p_old = d.p0

    # Update zero probability
    z_zero_e_obs = z_e_obs .* EM_E_z_zero_obs(ye, p_old, expert_ll_pos)
    z_pos_e_obs = z_e_obs .- z_zero_e_obs
    z_zero_e_lat = 0.0
    z_pos_e_lat = 0.0
    p_new = EM_M_zero(z_zero_e_obs, z_pos_e_obs, 0.0, 0.0, 0.0)

    # Update parameters: call its positive part
    tmp_exp = NegativeBinomialExpert(d.n, d.p)
    tmp_update = EM_M_expert_exact(tmp_exp,
                            ye,
                            expert_ll_pos,
                            z_pos_e_obs;
                            penalty = penalty, pen_pararms_jk = pen_pararms_jk)

    return ZINegativeBinomialExpert(p_new, tmp_update.n, tmp_update.p)

end