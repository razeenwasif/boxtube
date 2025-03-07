import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  Container, 
  Box, 
  Typography, 
  Paper, 
  List, 
  ListItem, 
  ListItemText, 
  ListItemIcon, 
  ListItemSecondaryAction, 
  IconButton, 
  Divider, 
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Alert
} from '@mui/material';
import { 
  Search, 
  History, 
  Delete, 
  TrendingUp, 
  Close 
} from '@mui/icons-material';
import { useSearch } from '../contexts/SearchContext';

const SearchHistory = () => {
  const [confirmClearOpen, setConfirmClearOpen] = useState(false);
  const { searchHistory, removeFromSearchHistory, clearSearchHistory } = useSearch();
  const navigate = useNavigate();
  
  // Format date to readable string
  const formatDate = (dateString) => {
    const date = new Date(dateString);
    const now = new Date();
    const diffMs = now - date;
    const diffSec = Math.floor(diffMs / 1000);
    const diffMin = Math.floor(diffSec / 60);
    const diffHour = Math.floor(diffMin / 60);
    const diffDay = Math.floor(diffHour / 24);
    
    if (diffDay > 0) {
      return diffDay === 1 ? 'Yesterday' : `${diffDay} days ago`;
    } else if (diffHour > 0) {
      return `${diffHour} ${diffHour === 1 ? 'hour' : 'hours'} ago`;
    } else if (diffMin > 0) {
      return `${diffMin} ${diffMin === 1 ? 'minute' : 'minutes'} ago`;
    } else {
      return 'Just now';
    }
  };
  
  // Handle search click
  const handleSearchClick = (term) => {
    navigate(`/search/${term}`);
  };
  
  // Handle remove search
  const handleRemoveSearch = (e, term) => {
    e.stopPropagation();
    removeFromSearchHistory(term);
  };
  
  // Handle clear all
  const handleClearAll = () => {
    clearSearchHistory();
    setConfirmClearOpen(false);
  };
  
  // Group searches by date
  const groupedSearches = searchHistory.reduce((acc, search) => {
    const date = new Date(search.timestamp);
    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    
    let group;
    if (date.toDateString() === today.toDateString()) {
      group = 'Today';
    } else if (date.toDateString() === yesterday.toDateString()) {
      group = 'Yesterday';
    } else {
      group = 'Earlier';
    }
    
    if (!acc[group]) {
      acc[group] = [];
    }
    
    acc[group].push(search);
    return acc;
  }, {});
  
  return (
    <Container maxWidth="md" sx={{ py: 4 }}>
      <Paper 
        elevation={3} 
        sx={{ 
          p: 3, 
          backgroundColor: 'var(--card-bg)',
          border: '1px solid rgba(0, 0, 0, 0.4)',
          borderRadius: '12px'
        }}
      >
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <History sx={{ color: 'var(--primary-color)', fontSize: 28 }} />
            <Typography variant="h4" color="var(--text-primary)" fontWeight="500">
              Search History
            </Typography>
          </Box>
          
          {searchHistory.length > 0 && (
            <Button
              variant="outlined"
              color="error"
              startIcon={<Delete />}
              onClick={() => setConfirmClearOpen(true)}
              sx={{
                borderColor: 'rgba(0, 0, 0, 0.4)',
                color: 'var(--text-secondary)',
                '&:hover': {
                  borderColor: 'var(--primary-color)',
                  color: 'var(--primary-color)',
                  backgroundColor: 'rgba(255, 0, 0, 0.08)'
                }
              }}
            >
              Clear All
            </Button>
          )}
        </Box>
        
        {searchHistory.length > 0 ? (
          Object.entries(groupedSearches).map(([group, searches]) => (
            <Box key={group} sx={{ mb: 3 }}>
              <Typography 
                variant="subtitle1" 
                color="var(--text-secondary)"
                sx={{ mb: 1, fontWeight: 500 }}
              >
                {group}
              </Typography>
              
              <Paper 
                variant="outlined" 
                sx={{ 
                  borderColor: 'rgba(0, 0, 0, 0.4)',
                  borderRadius: '8px',
                  overflow: 'hidden'
                }}
              >
                <List disablePadding>
                  {searches.map((search, index) => (
                    <Box key={`${search.term}-${search.timestamp}`}>
                      {index > 0 && <Divider sx={{ borderColor: 'rgba(0, 0, 0, 0.4)' }} />}
                      <ListItem 
                        button 
                        onClick={() => handleSearchClick(search.term)}
                        sx={{
                          '&:hover': {
                            backgroundColor: 'rgba(255, 0, 0, 0.08)'
                          }
                        }}
                      >
                        <ListItemIcon sx={{ minWidth: 40 }}>
                          <Search sx={{ color: 'var(--text-secondary)' }} />
                        </ListItemIcon>
                        <ListItemText 
                          primary={
                            <Typography color="var(--text-primary)">
                              {search.term}
                            </Typography>
                          }
                          secondary={
                            <Typography variant="body2" color="var(--text-secondary)">
                              {formatDate(search.timestamp)}
                            </Typography>
                          }
                        />
                        <ListItemSecondaryAction>
                          <IconButton 
                            edge="end" 
                            onClick={(e) => handleRemoveSearch(e, search.term)}
                            sx={{ color: 'var(--text-secondary)' }}
                          >
                            <Close />
                          </IconButton>
                        </ListItemSecondaryAction>
                      </ListItem>
                    </Box>
                  ))}
                </List>
              </Paper>
            </Box>
          ))
        ) : (
          <Box 
            sx={{ 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: 'center',
              justifyContent: 'center',
              py: 8,
              color: 'var(--text-secondary)'
            }}
          >
            <Search sx={{ fontSize: 60, mb: 2, opacity: 0.7 }} />
            <Typography variant="h6">No search history</Typography>
            <Typography variant="body2" sx={{ mt: 1 }}>
              Your search history will appear here
            </Typography>
          </Box>
        )}
        
        {/* Trending searches */}
        <Box sx={{ mt: 4 }}>
          <Typography 
            variant="h5" 
            color="var(--text-primary)" 
            sx={{ 
              display: 'flex', 
              alignItems: 'center', 
              gap: 1, 
              mb: 2 
            }}
          >
            <TrendingUp sx={{ color: 'var(--primary-color)' }} />
            Trending Searches
          </Typography>
          
          <Paper 
            variant="outlined" 
            sx={{ 
              borderColor: 'rgba(0, 0, 0, 0.4)',
              borderRadius: '8px',
              overflow: 'hidden',
              backgroundColor: 'rgba(0, 0, 0, 0.4)'
            }}
          >
            <List disablePadding>
              {['music videos', 'trending', 'news today', 'gaming', 'tutorials'].map((term, index) => (
                <Box key={term}>
                  {index > 0 && <Divider sx={{ borderColor: 'rgba(0, 0, 0, 0.4)' }} />}
                  <ListItem 
                    button 
                    onClick={() => handleSearchClick(term)}
                    sx={{
                      '&:hover': {
                        backgroundColor: 'rgba(255, 0, 0, 0.08)'
                      }
                    }}
                  >
                    <ListItemIcon sx={{ minWidth: 40 }}>
                      <TrendingUp sx={{ color: 'var(--primary-color)' }} />
                    </ListItemIcon>
                    <ListItemText 
                      primary={
                        <Typography color="var(--text-primary)">
                          {term}
                        </Typography>
                      }
                    />
                  </ListItem>
                </Box>
              ))}
            </List>
          </Paper>
        </Box>
      </Paper>
      
      {/* Confirmation Dialog */}
      <Dialog
        open={confirmClearOpen}
        onClose={() => setConfirmClearOpen(false)}
        PaperProps={{
          sx: {
            backgroundColor: 'rgba(0, 0, 0, 0.4)',
            border: '1px solid rgba(0, 0, 0, 0.4)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Clear Search History
        </DialogTitle>
        <DialogContent>
          <Alert severity="warning" sx={{ mb: 2 }}>
            This action cannot be undone.
          </Alert>
          <Typography color="var(--text-secondary)">
            Are you sure you want to clear your entire search history?
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={() => setConfirmClearOpen(false)}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleClearAll}
            color="error"
            variant="contained"
          >
            Clear History
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
};

export default SearchHistory; 