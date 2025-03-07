import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { 
  Container, 
  Box, 
  Typography, 
  Button,
  List,
  ListItem,
  ListItemText,
  ListItemIcon,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Alert,
  Grid,
  Card,
  CardContent,
  CardMedia,
  CardActionArea,
  IconButton,
  Menu,
  MenuItem
} from '@mui/material';
import { 
  PlaylistAdd, 
  MoreVert, 
  Edit, 
  Delete, 
  WatchLater, 
  Favorite, 
  VideoLibrary 
} from '@mui/icons-material';
import { usePlaylist } from '../contexts/PlaylistContext';

const Playlists = () => {
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [newPlaylistDescription, setNewPlaylistDescription] = useState('');
  const [editPlaylistId, setEditPlaylistId] = useState(null);
  const [deletePlaylistId, setDeletePlaylistId] = useState(null);
  const [menuAnchorEl, setMenuAnchorEl] = useState(null);
  const [activePlaylistId, setActivePlaylistId] = useState(null);
  
  const { 
    playlists, 
    createPlaylist, 
    deletePlaylist, 
    updatePlaylist, 
    getPlaylist 
  } = usePlaylist();
  
  const navigate = useNavigate();
  
  // Handle menu open
  const handleMenuOpen = (event, playlistId) => {
    event.stopPropagation();
    setMenuAnchorEl(event.currentTarget);
    setActivePlaylistId(playlistId);
  };
  
  // Handle menu close
  const handleMenuClose = () => {
    setMenuAnchorEl(null);
    setActivePlaylistId(null);
  };
  
  // Handle create dialog open
  const handleCreateDialogOpen = () => {
    setCreateDialogOpen(true);
  };
  
  // Handle create dialog close
  const handleCreateDialogClose = () => {
    setCreateDialogOpen(false);
    setNewPlaylistName('');
    setNewPlaylistDescription('');
  };
  
  // Handle create playlist
  const handleCreatePlaylist = () => {
    if (newPlaylistName.trim()) {
      createPlaylist(
        newPlaylistName.trim(), 
        newPlaylistDescription.trim()
      );
      
      handleCreateDialogClose();
    }
  };
  
  // Handle edit dialog open
  const handleEditDialogOpen = (playlistId) => {
    const playlist = getPlaylist(playlistId);
    if (playlist) {
      setEditPlaylistId(playlistId);
      setNewPlaylistName(playlist.name);
      setNewPlaylistDescription(playlist.description);
      setEditDialogOpen(true);
      handleMenuClose();
    }
  };
  
  // Handle edit dialog close
  const handleEditDialogClose = () => {
    setEditDialogOpen(false);
    setEditPlaylistId(null);
    setNewPlaylistName('');
    setNewPlaylistDescription('');
  };
  
  // Handle edit playlist
  const handleEditPlaylist = () => {
    if (newPlaylistName.trim() && editPlaylistId) {
      updatePlaylist(editPlaylistId, {
        name: newPlaylistName.trim(),
        description: newPlaylistDescription.trim()
      });
      
      handleEditDialogClose();
    }
  };
  
  // Handle delete dialog open
  const handleDeleteDialogOpen = (playlistId) => {
    setDeletePlaylistId(playlistId);
    setDeleteDialogOpen(true);
    handleMenuClose();
  };
  
  // Handle delete dialog close
  const handleDeleteDialogClose = () => {
    setDeleteDialogOpen(false);
    setDeletePlaylistId(null);
  };
  
  // Handle delete playlist
  const handleDeletePlaylist = () => {
    if (deletePlaylistId) {
      const success = deletePlaylist(deletePlaylistId);
      
      if (!success) {
        // Show error message for default playlists
        alert('Cannot delete default playlists');
      }
      
      handleDeleteDialogClose();
    }
  };
  
  // Handle playlist click
  const handlePlaylistClick = (playlistId) => {
    navigate(`/playlist/${playlistId}`);
  };
  
  // Get playlist icon
  const getPlaylistIcon = (playlist) => {
    if (playlist.id === 'watch-later') return <WatchLater sx={{ fontSize: 40 }} />;
    if (playlist.id === 'favorites') return <Favorite sx={{ fontSize: 40 }} />;
    return <VideoLibrary sx={{ fontSize: 40 }} />;
  };
  
  // Get playlist thumbnail
  const getPlaylistThumbnail = (playlist) => {
    if (playlist.videos.length > 0) {
      return playlist.videos[0].snippet?.thumbnails?.high?.url;
    }
    return null;
  };
  
  return (
    <Container maxWidth="lg" sx={{ py: 4 }}>
      <Box sx={{ 
        display: 'flex', 
        justifyContent: 'space-between', 
        alignItems: 'center', 
        mb: 4 
      }}>
        <Typography 
          variant="h4" 
          color="var(--text-primary)" 
          sx={{ fontWeight: 500 }}
        >
          Your Playlists
        </Typography>
        
        <Button
          variant="contained"
          startIcon={<PlaylistAdd />}
          onClick={handleCreateDialogOpen}
          sx={{
            backgroundColor: 'var(--primary-color)',
            '&:hover': {
              backgroundColor: 'var(--primary-color-dark)',
            }
          }}
        >
          Create Playlist
        </Button>
      </Box>
      
      <Grid container spacing={3}>
        {playlists.map((playlist) => (
          <Grid item xs={12} sm={6} md={4} key={playlist.id}>
            <Card 
              sx={{ 
                backgroundColor: 'var(--card-bg)',
                border: '1px solid var(--border-color)',
                borderRadius: '12px',
                overflow: 'hidden',
                transition: 'all 0.3s ease',
                '&:hover': {
                  transform: 'translateY(-4px)',
                  boxShadow: 'var(--card-hover-shadow)',
                  borderColor: 'var(--primary-color)',
                }
              }}
            >
              <CardActionArea onClick={() => handlePlaylistClick(playlist.id)}>
                {getPlaylistThumbnail(playlist) ? (
                  <CardMedia
                    component="img"
                    height="140"
                    image={getPlaylistThumbnail(playlist)}
                    alt={playlist.name}
                  />
                ) : (
                  <Box 
                    sx={{ 
                      height: 140, 
                      display: 'flex', 
                      alignItems: 'center', 
                      justifyContent: 'center',
                      backgroundColor: 'rgba(255, 0, 0, 0.1)',
                    }}
                  >
                    {getPlaylistIcon(playlist)}
                  </Box>
                )}
                
                <CardContent>
                  <Box sx={{ 
                    display: 'flex', 
                    justifyContent: 'space-between', 
                    alignItems: 'flex-start' 
                  }}>
                    <Box>
                      <Typography 
                        variant="h6" 
                        component="div" 
                        color="var(--text-primary)"
                        sx={{
                          display: '-webkit-box',
                          overflow: 'hidden',
                          WebkitBoxOrient: 'vertical',
                          WebkitLineClamp: 1,
                        }}
                      >
                        {playlist.name}
                      </Typography>
                      
                      <Typography 
                        variant="body2" 
                        color="var(--text-secondary)"
                        sx={{ mt: 0.5 }}
                      >
                        {playlist.videos.length} {playlist.videos.length === 1 ? 'video' : 'videos'}
                      </Typography>
                      
                      {playlist.description && (
                        <Typography 
                          variant="body2" 
                          color="var(--text-secondary)"
                          sx={{
                            mt: 1,
                            display: '-webkit-box',
                            overflow: 'hidden',
                            WebkitBoxOrient: 'vertical',
                            WebkitLineClamp: 2,
                          }}
                        >
                          {playlist.description}
                        </Typography>
                      )}
                    </Box>
                    
                    <IconButton
                      onClick={(e) => handleMenuOpen(e, playlist.id)}
                      sx={{ 
                        color: 'var(--text-secondary)',
                        '&:hover': { color: 'var(--primary-color)' }
                      }}
                    >
                      <MoreVert />
                    </IconButton>
                  </Box>
                </CardContent>
              </CardActionArea>
            </Card>
          </Grid>
        ))}
      </Grid>
      
      {/* Playlist Menu */}
      <Menu
        anchorEl={menuAnchorEl}
        open={Boolean(menuAnchorEl)}
        onClose={handleMenuClose}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
          }
        }}
      >
        <MenuItem 
          onClick={() => handleEditDialogOpen(activePlaylistId)}
          sx={{ 
            color: 'var(--text-primary)',
            '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
          }}
        >
          <ListItemIcon sx={{ color: 'var(--text-secondary)' }}>
            <Edit />
          </ListItemIcon>
          <ListItemText primary="Edit" />
        </MenuItem>
        
        <MenuItem 
          onClick={() => handleDeleteDialogOpen(activePlaylistId)}
          sx={{ 
            color: 'var(--text-primary)',
            '&:hover': { backgroundColor: 'rgba(255, 0, 0, 0.08)' }
          }}
        >
          <ListItemIcon sx={{ color: 'var(--text-secondary)' }}>
            <Delete />
          </ListItemIcon>
          <ListItemText primary="Delete" />
        </MenuItem>
      </Menu>
      
      {/* Create Playlist Dialog */}
      <Dialog 
        open={createDialogOpen} 
        onClose={handleCreateDialogClose}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Create new playlist
        </DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            label="Name"
            fullWidth
            variant="outlined"
            value={newPlaylistName}
            onChange={(e) => setNewPlaylistName(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
          <TextField
            margin="dense"
            label="Description (optional)"
            fullWidth
            variant="outlined"
            multiline
            rows={2}
            value={newPlaylistDescription}
            onChange={(e) => setNewPlaylistDescription(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={handleCreateDialogClose}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleCreatePlaylist}
            variant="contained"
            disabled={!newPlaylistName.trim()}
            sx={{
              backgroundColor: 'var(--primary-color)',
              '&:hover': {
                backgroundColor: 'var(--primary-color-dark)',
              },
              '&.Mui-disabled': {
                backgroundColor: 'rgba(255, 0, 0, 0.3)',
              }
            }}
          >
            Create
          </Button>
        </DialogActions>
      </Dialog>
      
      {/* Edit Playlist Dialog */}
      <Dialog 
        open={editDialogOpen} 
        onClose={handleEditDialogClose}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Edit playlist
        </DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            label="Name"
            fullWidth
            variant="outlined"
            value={newPlaylistName}
            onChange={(e) => setNewPlaylistName(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
          <TextField
            margin="dense"
            label="Description (optional)"
            fullWidth
            variant="outlined"
            multiline
            rows={2}
            value={newPlaylistDescription}
            onChange={(e) => setNewPlaylistDescription(e.target.value)}
            sx={{
              mb: 2,
              '& .MuiOutlinedInput-root': {
                '& fieldset': {
                  borderColor: 'var(--border-color)',
                },
                '&:hover fieldset': {
                  borderColor: 'var(--text-secondary)',
                },
                '&.Mui-focused fieldset': {
                  borderColor: 'var(--primary-color)',
                },
              },
              '& .MuiInputLabel-root': {
                color: 'var(--text-secondary)',
              },
              '& .MuiInputBase-input': {
                color: 'var(--text-primary)',
              },
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={handleEditDialogClose}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleEditPlaylist}
            variant="contained"
            disabled={!newPlaylistName.trim()}
            sx={{
              backgroundColor: 'var(--primary-color)',
              '&:hover': {
                backgroundColor: 'var(--primary-color-dark)',
              },
              '&.Mui-disabled': {
                backgroundColor: 'rgba(255, 0, 0, 0.3)',
              }
            }}
          >
            Save
          </Button>
        </DialogActions>
      </Dialog>
      
      {/* Delete Playlist Dialog */}
      <Dialog
        open={deleteDialogOpen}
        onClose={handleDeleteDialogClose}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Delete Playlist
        </DialogTitle>
        <DialogContent>
          <Alert severity="warning" sx={{ mb: 2 }}>
            This action cannot be undone.
          </Alert>
          <Typography color="var(--text-secondary)">
            Are you sure you want to delete this playlist?
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={handleDeleteDialogClose}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={handleDeletePlaylist}
            color="error"
            variant="contained"
          >
            Delete
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
};

export default Playlists; 