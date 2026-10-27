package com.max.loja.push;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionTemplate;

/** Entrega a fila de avisos: manda pelo Firebase, tenta de novo se falhar e registra a confirmação. */
@Component
public class PushOutboxWorker {

    private static final Logger log = LoggerFactory.getLogger(PushOutboxWorker.class);
    private static final int BATCH = 50;

    private final PushOutbox outbox;
    private final PushSender sender;
    private final PushProperties props;
    private final TransactionTemplate tx;
    private final ObjectMapper json;
    private final Clock clock;

    PushOutboxWorker(PushOutbox outbox, PushSender sender, PushProperties props, TransactionTemplate tx, ObjectMapper json,
                     Clock clock) {
        this.outbox = outbox;
        this.sender = sender;
        this.props = props;
        this.tx = tx;
        this.json = json;
        this.clock = clock;
    }

    @Scheduled(fixedDelayString = "${app.push.worker-ms:10000}", initialDelayString = "${app.push.worker-ms:10000}")
    public void run() {
        if (props.configured()) {
            drain();
        }
    }

    /** Entrega tudo o que está vencido na fila (em lotes). */
    public void drain() {
        int total = 0;
        int batch;
        do {
            batch = tx.execute(status -> deliver(outbox.claimDue(BATCH, LocalDateTime.now(clock))));
            total += batch;
        } while (batch == BATCH && total < 1000);
        LocalDateTime now = LocalDateTime.now(clock);
        outbox.expireOld(now.minusDays(1));
        outbox.purge(now.minusDays(30));
        if (total > 0) {
            log.info("Fila de push: {} avisos processados", total);
        }
    }

    /** Entrega um lote dentro da transação que travou as linhas. Devolve quantos processou. */
    int deliver(List<PushOutbox.Due> due) {
        for (PushOutbox.Due d : due) {
            LocalDateTime now = LocalDateTime.now(clock);
            Map<String, String> data;
            try {
                data = new java.util.HashMap<>(json.readValue(d.data(), new TypeReference<Map<String, String>>() { }));
            } catch (Exception e) {
                data = new java.util.HashMap<>();
            }
            data.put("messageId", d.publicId()); // o app devolve este código para confirmar o recebimento
            PushSender.Result r = sender.send(d.token(), d.title(), d.body(), data);
            switch (r) {
                case SENT -> outbox.markSent(d.id(), now);
                case INVALID_TOKEN -> {
                    outbox.markInvalid(d.id());
                    outbox.removeDevice(d.deviceId());
                }
                case FAILED -> outbox.markFailed(d.id(), d.attempts(), now, "o Firebase não aceitou o aviso");
                case DISABLED -> {
                    return 0; // sem Firebase configurado: deixa tudo na fila
                }
            }
        }
        return due.size();
    }
}
