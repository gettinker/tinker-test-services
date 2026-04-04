package com.tinker.orders;

import java.util.List;

public class Order {

    private String id;
    private String userId;
    private List<String> items;
    private double total;
    private String status;
    private String createdAt;

    public Order() {}

    public Order(String id, String userId, List<String> items,
                 double total, String status, String createdAt) {
        this.id        = id;
        this.userId    = userId;
        this.items     = items;
        this.total     = total;
        this.status    = status;
        this.createdAt = createdAt;
    }

    public String getId()        { return id; }
    public String getUserId()    { return userId; }
    public List<String> getItems() { return items; }
    public double getTotal()     { return total; }
    public String getStatus()    { return status; }
    public String getCreatedAt() { return createdAt; }

    public void setId(String id)            { this.id = id; }
    public void setUserId(String userId)    { this.userId = userId; }
    public void setItems(List<String> items){ this.items = items; }
    public void setTotal(double total)      { this.total = total; }
    public void setStatus(String status)    { this.status = status; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
