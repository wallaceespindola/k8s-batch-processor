package com.wallaceespindola.k8sbatchprocessor.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.wallaceespindola.k8sbatchprocessor.dto.BatchRequest;
import com.wallaceespindola.k8sbatchprocessor.service.BatchJobService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(BatchController.class)
class BatchControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private BatchJobService batchJobService;

    @Test
    void start_acceptsValidRequest() throws Exception {
        when(batchJobService.isRunning()).thenReturn(false);
        doNothing().when(batchJobService).startJob(any());

        mockMvc.perform(post("/api/batch/start")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new BatchRequest(100, 4))))
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.message").value("Batch job started"));
    }

    @Test
    void start_returns400_whenJobAlreadyRunning() throws Exception {
        when(batchJobService.isRunning()).thenReturn(true);

        mockMvc.perform(post("/api/batch/start")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(new BatchRequest(100, 4))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
    }

    @Test
    void start_returns400_forInvalidAccountCount() throws Exception {
        mockMvc.perform(post("/api/batch/start")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"accountCount\": 0, \"podCount\": 4}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void reset_returnsOk_whenNotRunning() throws Exception {
        when(batchJobService.isRunning()).thenReturn(false);
        doNothing().when(batchJobService).reset();

        mockMvc.perform(post("/api/batch/reset"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Reset successful"));
    }

    @Test
    void reset_returns400_whenRunning() throws Exception {
        when(batchJobService.isRunning()).thenReturn(true);

        mockMvc.perform(post("/api/batch/reset"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
    }

    @Test
    void health_returnsUp() throws Exception {
        when(batchJobService.getJobStatus()).thenReturn("IDLE");

        mockMvc.perform(get("/api/batch/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.jobStatus").value("IDLE"));
    }
}
