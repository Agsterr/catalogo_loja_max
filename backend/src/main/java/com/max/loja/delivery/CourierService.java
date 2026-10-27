package com.max.loja.delivery;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDateTime;
import java.util.List;

import com.max.loja.auth.AppUser;
import com.max.loja.auth.AppUserRepository;
import com.max.loja.delivery.CourierDtos.AdminCourier;
import com.max.loja.delivery.CourierDtos.EarningsResponse;
import com.max.loja.delivery.CourierDtos.JobCard;
import com.max.loja.delivery.CourierDtos.JobDetail;
import com.max.loja.delivery.CourierDtos.Money2;
import com.max.loja.delivery.CourierDtos.OnlineRequest;
import com.max.loja.delivery.CourierDtos.ProfileRequest;
import com.max.loja.delivery.CourierDtos.ProfileResponse;
import com.max.loja.delivery.CourierDtos.RegisterRequest;
import com.max.loja.event.StoreEvents;
import com.max.loja.order.CustomerOrder;
import com.max.loja.order.OrderService;
import com.max.loja.order.OrderStatus;
import com.max.loja.push.PushNotifier;
import com.max.loja.shared.BusinessException;
import com.max.loja.shared.NotFoundException;
import com.max.loja.shared.PageResponse;
import com.max.loja.shared.RateLimiter;
import com.max.loja.shared.Search;
import com.max.loja.shared.TenantRunner;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * Tudo do entregador: cadastro, região, mural, aceitar, coletar, entregar e ganhos. Ações que mexem no pedido rodam numa
 * transação nova NO TENANT da loja ({@link TenantRunner}), travando o pedido antes da corrida (ordem única de locks).
 */
@Service
public class CourierService {

    private final CourierRepository couriers;
    private final DeliveryJobRepository jobs;
    private final AppUserRepository users;
    private final OrderService orders;
    private final DispatchService dispatch;
    private final DeliveryProperties props;
    private final PushNotifier push;
    private final RateLimiter rateLimiter;
    private final ApplicationEventPublisher events;
    private final TenantRunner runner;
    private final Clock clock;

    public CourierService(CourierRepository couriers, DeliveryJobRepository jobs, AppUserRepository users,
                          OrderService orders, DispatchService dispatch, DeliveryProperties props, PushNotifier push,
                          RateLimiter rateLimiter, ApplicationEventPublisher events, TenantRunner runner, Clock clock) {
        this.couriers = couriers;
        this.jobs = jobs;
        this.users = users;
        this.orders = orders;
        this.dispatch = dispatch;
        this.props = props;
        this.push = push;
        this.rateLimiter = rateLimiter;
        this.events = events;
        this.runner = runner;
        this.clock = clock;
    }

    // --- cadastro e perfil ---

    /** Cria o perfil (chamado no cadastro, na mesma transação da conta). Fica pendente até a plataforma aprovar. */
    @Transactional
    public Courier createProfile(AppUser user, RegisterRequest req) {
        Courier c = new Courier();
        c.setUserId(user.getId());
        c.setPhone(req.phone().trim());
        c.setVehicle(req.vehicle());
        c.setPlate(blank(req.plate()));
        c.setCity(req.city().trim());
        c.setState(req.state().trim().toUpperCase());
        c.setBaseLat(req.baseLat());
        c.setBaseLng(req.baseLng());
        c.setRadiusKm(req.radiusKm() == null ? 10 : req.radiusKm());
        c.setCreatedAt(LocalDateTime.now(clock));
        return couriers.save(c);
    }

    @Transactional(readOnly = true)
    public ProfileResponse profile(Long id) {
        return profile(courier(id));
    }

    @Transactional
    public ProfileResponse update(Long id, ProfileRequest req) {
        Courier c = courier(id);
        c.setPhone(req.phone().trim());
        c.setVehicle(req.vehicle());
        c.setPlate(blank(req.plate()));
        c.setCity(req.city().trim());
        c.setState(req.state().trim().toUpperCase());
        boolean hasPoint = req.baseLat() != null && req.baseLng() != null;
        c.setBaseLat(hasPoint ? req.baseLat() : null);
        c.setBaseLng(hasPoint ? req.baseLng() : null);
        c.setRadiusKm(req.radiusKm());
        return profile(c);
    }

    /** Liga/desliga o recebimento de corridas; a posição enviada junto vale como a de agora. */
    @Transactional
    public ProfileResponse setOnline(Long id, OnlineRequest req) {
        Courier c = approved(id);
        if (req.online() && req.lat() == null && c.getBaseLat() == null) {
            throw new BusinessException("Ligue a localização ou cadastre o ponto da sua região para receber corridas.");
        }
        c.setOnline(req.online());
        position(c, req.lat(), req.lng());
        return profile(c);
    }

    // --- mural e corridas ---

    /** Corridas abertas dentro do raio do entregador, da mais perto para a mais longe. */
    @Transactional
    public PageResponse<JobCard> openJobs(Long id, Double lat, Double lng, Integer page, Integer size) {
        Courier c = approved(id);
        position(c, lat, lng);
        Double[] ref = reference(c);
        if (ref == null) {
            throw new BusinessException("Ligue a localização ou cadastre o ponto da sua região para ver as corridas.");
        }
        double radius = c.getRadiusKm();
        double dLat = radius / 111.0;
        double dLng = radius / (111.0 * Math.max(0.2, Math.cos(Math.toRadians(ref[0]))));
        Page<DeliveryJob> result = jobs.openNear(ref[0], ref[1], radius, ref[0] - dLat, ref[0] + dLat, ref[1] - dLng,
                ref[1] + dLng, LocalDateTime.now(clock), PageResponse.request(page, size, Sort.unsorted()));
        return PageResponse.of(result, j -> new JobCard(j.getId(), j.getStoreName(), j.getPickupAddress(), j.getCity(),
                Math.round(km(ref[0], ref[1], j.getPickupLat(), j.getPickupLng()) * 10) / 10.0, j.getDistanceKm(),
                j.getCourierFee(), j.getItemCount(), j.getCreatedAt(), j.getExpiresAt()));
    }

    @Transactional(readOnly = true)
    public List<JobDetail> active(Long id) {
        approved(id);
        return jobs.findByCourierIdAndStatusInOrderByAcceptedAtDesc(id, List.of(JobStatus.ACCEPTED, JobStatus.PICKED_UP))
                .stream().map(this::detail).toList();
    }

    @Transactional(readOnly = true)
    public PageResponse<JobDetail> history(Long id, Integer page, Integer size) {
        approved(id);
        return PageResponse.of(jobs.findByCourierIdAndStatusInOrderByIdDesc(id, List.of(JobStatus.DELIVERED, JobStatus.CANCELED),
                PageResponse.request(page, size, Sort.unsorted())), this::detail);
    }

    @Transactional(readOnly = true)
    public JobDetail job(Long courierId, Long jobId) {
        return detail(mine(courierId, jobId));
    }

    /** Aceita a corrida: atômico (só um entregador consegue) e respeita o limite de corridas ao mesmo tempo. */
    public JobDetail accept(Long courierId, Long jobId) {
        DeliveryJob peek = jobs.findById(jobId).orElseThrow(() -> new NotFoundException("Corrida não encontrada"));
        return runner.call(peek.getTenantId(), () -> {
            Courier c = couriers.lock(courierId).orElseThrow(() -> new NotFoundException("Entregador não encontrado"));
            requireApproved(c);
            if (jobs.countActive(courierId) >= props.maxActiveJobs()) {
                throw new BusinessException("Você já está com " + props.maxActiveJobs() + " corridas. Conclua uma antes de aceitar outra.");
            }
            orders.lock(peek.getOrderId());
            if (jobs.accept(jobId, courierId, LocalDateTime.now(clock)) == 0) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Essa corrida não está mais disponível (outro entregador aceitou ou ela expirou).");
            }
            events.publishEvent(new StoreEvents.DeliveryAccepted(jobId));
            return detail(jobs.findById(jobId).orElseThrow());
        });
    }

    /** Coleta na loja: o entregador digita o código que a loja vê no pedido. O pedido vira "saiu para entrega". */
    public JobDetail pickUp(Long courierId, Long jobId, String code) {
        DeliveryJob peek = mine(courierId, jobId);
        attempt("job-pickup", peek);
        return runner.call(peek.getTenantId(), () -> {
            CustomerOrder order = orders.lock(peek.getOrderId());
            DeliveryJob job = mine(courierId, jobId);
            if (job.getStatus() != JobStatus.ACCEPTED) {
                throw new BusinessException("Esta corrida está \"" + job.getStatus().label().toLowerCase() + "\".");
            }
            checkCode(job, code, job.getPickupCode(), "Código de coleta incorreto. Peça à loja o código do pedido.");
            job.setStatus(JobStatus.PICKED_UP);
            job.setPickedUpAt(LocalDateTime.now(clock));
            orders.courierStep(order, OrderStatus.SHIPPED, courierId, name(courierId));
            return detail(job);
        });
    }

    /** Entrega: o entregador digita o código que o cliente vê no pedido. O pedido vira "entregue". */
    public JobDetail deliver(Long courierId, Long jobId, String code) {
        DeliveryJob peek = mine(courierId, jobId);
        attempt("job-deliver", peek);
        return runner.call(peek.getTenantId(), () -> {
            CustomerOrder order = orders.lock(peek.getOrderId());
            DeliveryJob job = mine(courierId, jobId);
            if (job.getStatus() != JobStatus.PICKED_UP) {
                throw new BusinessException("Confirme a coleta antes de entregar.");
            }
            checkCode(job, code, job.getDeliveryCode(), "Código de entrega incorreto. Peça ao cliente o código do pedido.");
            job.setStatus(JobStatus.DELIVERED);
            job.setDeliveredAt(LocalDateTime.now(clock));
            couriers.lock(courierId).ifPresent(c -> c.setDeliveredCount(c.getDeliveredCount() + 1));
            orders.courierStep(order, OrderStatus.DELIVERED, courierId, name(courierId));
            events.publishEvent(new StoreEvents.DeliveryDone(jobId));
            return detail(job);
        });
    }

    /** Desistência antes de coletar: a corrida volta ao mural e a loja é avisada. Depois da coleta, só pelo suporte. */
    public void cancel(Long courierId, Long jobId, String reason) {
        DeliveryJob peek = mine(courierId, jobId);
        runner.run(peek.getTenantId(), () -> {
            orders.lock(peek.getOrderId());
            DeliveryJob job = mine(courierId, jobId);
            if (job.getStatus() != JobStatus.ACCEPTED) {
                throw new BusinessException("Só dá para desistir antes de coletar o pedido. Depois, fale com o suporte.");
            }
            couriers.lock(courierId).ifPresent(c -> c.setCanceledCount(c.getCanceledCount() + 1));
            dispatch.reopen(job);
            events.publishEvent(new StoreEvents.DeliveryReopened(jobId));
        });
    }

    @Transactional(readOnly = true)
    public EarningsResponse earnings(Long id) {
        approved(id);
        LocalDateTime now = LocalDateTime.now(clock);
        LocalDateTime today = now.toLocalDate().atStartOfDay();
        LocalDateTime week = today.minusDays(now.getDayOfWeek().getValue() - DayOfWeek.MONDAY.getValue());
        LocalDateTime month = today.withDayOfMonth(1);
        return new EarningsResponse(sum(id, today), sum(id, week), sum(id, month));
    }

    private Money2 sum(Long id, LocalDateTime since) {
        DeliveryJobRepository.Earnings e = jobs.earnings(id, since);
        return new Money2(e.getTotal(), e.getCount());
    }

    // --- administração da plataforma ---

    @Transactional(readOnly = true)
    public PageResponse<AdminCourier> adminList(CourierStatus status, String q, Integer page, Integer size) {
        Page<Courier> result = couriers.search(status == null ? "" : status.name(), Search.like(q == null ? "" : q),
                PageResponse.request(page, size, Sort.unsorted()));
        var byId = new java.util.HashMap<Long, AppUser>();
        users.findAllById(result.getContent().stream().map(Courier::getUserId).toList()).forEach(u -> byId.put(u.getId(), u));
        return PageResponse.of(result, c -> {
            AppUser u = byId.get(c.getUserId());
            return new AdminCourier(c.getUserId(), u == null ? "?" : u.getName(), u == null ? "" : u.getEmail(), c.getPhone(),
                    c.getVehicle(), c.getPlate(), c.getCity(), c.getState(), c.getStatus(), c.getStatusReason(), c.isOnline(),
                    c.getDeliveredCount(), c.getCanceledCount(), c.getCreatedAt());
        });
    }

    @Transactional
    public void setStatus(Long id, CourierStatus status, String reason) {
        Courier c = courier(id);
        c.setStatus(status);
        c.setStatusReason(blank(reason));
        if (status == CourierStatus.APPROVED) {
            c.setApprovedAt(LocalDateTime.now(clock));
        } else {
            c.setOnline(false);
        }
        String title = status == CourierStatus.APPROVED ? "Cadastro aprovado!" : "Cadastro bloqueado";
        String body = status == CourierStatus.APPROVED ? "Você já pode ligar o app e receber corridas."
                : (c.getStatusReason() == null ? "Fale com o suporte da plataforma." : c.getStatusReason());
        push.toUser(id, "courier-status:" + id + ":" + status + ":" + System.currentTimeMillis() / 1000, title, body,
                java.util.Map.of("type", "courier", "kind", "COURIER_STATUS"));
    }

    // --- apoio ---

    private Courier courier(Long id) {
        return couriers.findById(id).orElseThrow(() -> new NotFoundException("Cadastro de entregador não encontrado"));
    }

    private Courier approved(Long id) {
        Courier c = courier(id);
        requireApproved(c);
        return c;
    }

    private static void requireApproved(Courier c) {
        if (c.getStatus() == CourierStatus.PENDING) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Seu cadastro está em análise. Avisaremos quando for aprovado.");
        }
        if (c.getStatus() == CourierStatus.BLOCKED) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, c.getStatusReason() == null
                    ? "Seu cadastro de entregador está bloqueado." : "Cadastro bloqueado: " + c.getStatusReason());
        }
    }

    private DeliveryJob mine(Long courierId, Long jobId) {
        return jobs.findById(jobId).filter(j -> courierId.equals(j.getCourierId()))
                .orElseThrow(() -> new NotFoundException("Corrida não encontrada"));
    }

    /**
     * Até 5 tentativas por corrida e entregador a cada 10 minutos (o código tem só 4 dígitos). Conta fora da transação
     * da ação: um código errado desfaz a ação, mas a tentativa precisa ficar registrada.
     */
    private void attempt(String kind, DeliveryJob job) {
        rateLimiter.check(kind + ":" + job.getId() + ":" + job.getCourierId(), 5);
    }

    private void checkCode(DeliveryJob job, String typed, String expected, String message) {
        if (typed == null || !java.security.MessageDigest.isEqual(typed.trim().getBytes(), expected.getBytes())) {
            throw new BusinessException(message);
        }
    }

    private void position(Courier c, Double lat, Double lng) {
        if (lat != null && lng != null) {
            c.setLastLat(lat);
            c.setLastLng(lng);
            c.setLastSeenAt(LocalDateTime.now(clock));
        }
    }

    /** Ponto de referência: posição recente do app ou a base cadastrada. */
    private Double[] reference(Courier c) {
        if (c.getLastLat() != null && c.getLastSeenAt() != null
                && c.getLastSeenAt().isAfter(LocalDateTime.now(clock).minus(props.freshPosition()))) {
            return new Double[] {c.getLastLat(), c.getLastLng()};
        }
        return c.getBaseLat() == null ? null : new Double[] {c.getBaseLat(), c.getBaseLng()};
    }

    private String name(Long userId) {
        return users.findById(userId).map(AppUser::getName).orElse("Entregador");
    }

    private ProfileResponse profile(Courier c) {
        AppUser u = users.findById(c.getUserId()).orElseThrow();
        return new ProfileResponse(c.getUserId(), u.getName(), u.getEmail(), c.getPhone(), c.getVehicle(), c.getVehicle().label(),
                c.getPlate(), c.getCity(), c.getState(), c.getBaseLat(), c.getBaseLng(), c.getRadiusKm(), c.getStatus(),
                c.getStatusReason(), c.isOnline(), c.getDeliveredCount(), c.getCanceledCount(), c.getCreatedAt());
    }

    /** Detalhe da corrida: endereço e dados do cliente só enquanto ela é do entregador. */
    private JobDetail detail(DeliveryJob j) {
        boolean reveal = j.getStatus().active() || j.getStatus() == JobStatus.DELIVERED;
        return new JobDetail(j.getId(), j.getOrderCode(), j.getStatus().name(), j.getStatus().label(), j.getStoreName(),
                j.getPickupAddress(), j.getPickupLat(), j.getPickupLng(), reveal ? j.getDropoffAddress() : null,
                reveal ? j.getDropoffLat() : null, reveal ? j.getDropoffLng() : null, reveal ? j.getCustomerName() : null,
                j.getStatus().active() ? j.getCustomerPhone() : null, j.getDistanceKm(), j.getCourierFee(), j.getItemCount(),
                j.getAcceptedAt(), j.getPickedUpAt(), j.getDeliveredAt());
    }

    private static double km(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.pow(Math.sin(dLat / 2), 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) * Math.pow(Math.sin(dLng / 2), 2);
        return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
