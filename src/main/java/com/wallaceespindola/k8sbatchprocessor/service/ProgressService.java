package com.wallaceespindola.k8sbatchprocessor.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.wallaceespindola.k8sbatchprocessor.dto.ProgressEvent;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

@Slf4j
@Service
public class ProgressService {

    private final List<SseEmitter> emitters = new CopyOnWriteArrayList<>();
    private final ObjectMapper objectMapper;

    public ProgressService() {
        this.objectMapper = new ObjectMapper();
        this.objectMapper.registerModule(new JavaTimeModule());
        this.objectMapper.disable(com.fasterxml.jackson.databind.SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
    }

    public SseEmitter subscribe() {
        SseEmitter emitter = new SseEmitter(300_000L); // 5-minute timeout
        emitters.add(emitter);
        emitter.onCompletion(() -> emitters.remove(emitter));
        emitter.onTimeout(() -> {
            emitter.complete();
            emitters.remove(emitter);
        });
        emitter.onError(e -> emitters.remove(emitter));
        log.debug("New SSE subscriber. Total emitters: {}", emitters.size());
        return emitter;
    }

    public void broadcast(ProgressEvent event) {
        if (emitters.isEmpty()) return;

        // Serialize JSON once — reused for all emitters
        String json;
        try {
            json = objectMapper.writeValueAsString(event);
        } catch (Exception e) {
            log.error("Failed to serialize SSE event: {}", e.getMessage());
            return;
        }

        List<SseEmitter> dead = new ArrayList<>();
        for (SseEmitter emitter : emitters) {
            // SseEmitter.send() is NOT thread-safe — multiple pod threads call broadcast()
            // concurrently. Synchronize per-emitter to prevent concurrent write corruption.
            synchronized (emitter) {
                try {
                    emitter.send(SseEmitter.event().name("progress").data(json));
                } catch (Exception e) {
                    dead.add(emitter);
                    log.debug("Removing dead SSE emitter: {}", e.getMessage());
                }
            }
        }
        emitters.removeAll(dead);
    }

    public int getSubscriberCount() {
        return emitters.size();
    }
}
